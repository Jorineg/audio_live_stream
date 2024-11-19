import { decodeADPCM8Bit, resampleAudioData } from './audioUtils.js';

const playButton = document.getElementById('playButton');
const statusMessage = document.getElementById('statusMessage');
const visualizer = document.getElementById('visualizer');
const visualizerContext = visualizer.getContext('2d');
let audioContext;
let webSocket;
let micStatus = 'mic_active';
let isPlaying = false;
let scheduledTime = 0;
const BUFFER_SIZE = 2048;
let visualizerData = new Float32Array(BUFFER_SIZE);
let sampleRate = 22000;
let adpcmCompression = false;
const MIN_BUFFER_DURATION = 0.15;
const MAX_BUFFER_DURATION = 1.2;
let targetBufferDuration = MIN_BUFFER_DURATION;
let meanInterval = 0;
let variance = 0;
let stdDeviation = 0;
let recommendedBuffer = 0;
let bufferLatency = 0;
let meanBufferLatency = 0;
const MEAN_BUFFER_LATENCY_EMA_FACTOR = 0.995;

// Variables to track packet arrival times and compute jitter
let lastPacketArrivalTime = null;
let packetIntervals = [];
const JITTER_WINDOW_SIZE = 2000; // Number of intervals to keep for calculations

// Set visualizer size
function resizeVisualizer() {
    visualizer.width = window.innerWidth;
    visualizer.height = 100;
    drawWaveform();
}

window.addEventListener('resize', resizeVisualizer);
resizeVisualizer();

// Add these variables at the top with other declarations
let reconnectInterval = null;
const connectionOverlay = document.getElementById('connectionOverlay');
let lastHeartbeatTime = Date.now();
let heartbeatCheckInterval = null;
const HEARTBEAT_TIMEOUT = 3000; // Consider connection lost after 3 seconds without heartbeat

// Replace the existing WebSocket initialization with this function
function initializeWebSocket() {
    if (webSocket && webSocket.readyState !== WebSocket.CLOSED) return;

    // Clear any existing heartbeat check
    if (heartbeatCheckInterval) {
        clearInterval(heartbeatCheckInterval);
    }

    webSocket = new WebSocket('ws://' + window.location.host);
    webSocket.binaryType = 'arraybuffer';

    webSocket.onopen = () => {
        console.log('WebSocket connection opened');
        connectionOverlay.classList.add('hidden');
        clearInterval(reconnectInterval);
        reconnectInterval = null;
        lastHeartbeatTime = Date.now();

        // Start heartbeat checking
        heartbeatCheckInterval = setInterval(() => {
            const timeSinceLastHeartbeat = Date.now() - lastHeartbeatTime;
            if (timeSinceLastHeartbeat > HEARTBEAT_TIMEOUT) {
                console.log('Heartbeat timeout - connection lost');
                webSocket.close();
                connectionOverlay.classList.remove('hidden');

                // Only set up reconnect interval if not already trying to reconnect
                if (!reconnectInterval) {
                    reconnectInterval = setInterval(() => {
                        console.log('Attempting to reconnect...');
                        initializeWebSocket();
                    }, 2000);
                }
            }
        }, 1000);

        statusMessage.textContent = 'Click to start audio';
        updateStatusMessage();

        // If we were playing before disconnection, restart playing
        if (isPlaying) {
            startStream();
        }
    };

    webSocket.onclose = () => {
        console.log('WebSocket connection closed');
        connectionOverlay.classList.remove('hidden');

        // Clear heartbeat check on close
        if (heartbeatCheckInterval) {
            clearInterval(heartbeatCheckInterval);
            heartbeatCheckInterval = null;
        }
        // Only set up reconnect interval if not already trying to reconnect
        if (!reconnectInterval) {
            reconnectInterval = setInterval(() => {
                console.log('Attempting to reconnect...');
                initializeWebSocket();
            }, 2000); // Try to reconnect every 2 seconds
        }
    };

    webSocket.onmessage = (event) => {
        if (typeof event.data === 'string') {
            if (event.data === 'mic_active' || event.data === 'mic_muted') {
                micStatus = event.data;
                updateStatusMessage();
                if (micStatus === 'mic_muted') {
                    resetVisualizer();
                }
            } else if (event.data.startsWith('time:')) {
                // Update heartbeat timestamp
                lastHeartbeatTime = Date.now();
                webSocket.send(event.data);
            }
        } else if (event.data instanceof ArrayBuffer && isPlaying) {
            if (micStatus === 'mic_muted') return;

            // Measure packet arrival intervals
            const currentTime = performance.now();

            if (lastPacketArrivalTime !== null) {
                const interval = currentTime - lastPacketArrivalTime;
                packetIntervals.push(interval);

                if (packetIntervals.length > JITTER_WINDOW_SIZE) {
                    packetIntervals.shift(); // Keep the window size fixed
                }

                // Calculate mean and standard deviation
                meanInterval = packetIntervals.reduce((a, b) => a + b, 0) / packetIntervals.length;
                variance = packetIntervals.reduce((a, b) => a + Math.pow(b - meanInterval, 2), 0) / packetIntervals.length;
                stdDeviation = Math.sqrt(variance);

                // Adjust targetBufferDuration to cover 99% of the delays
                recommendedBuffer = (meanInterval + 4 * stdDeviation) / 1000; // Convert ms to seconds
                targetBufferDuration = Math.min(MAX_BUFFER_DURATION, Math.max(MIN_BUFFER_DURATION, recommendedBuffer));
            }

            lastPacketArrivalTime = currentTime;

            // Split off first byte that encodes header information
            const header = new Uint8Array(event.data, 0, 1)[0];
            const body = new Uint8Array(event.data.byteLength - 1);
            body.set(new Uint8Array(event.data, 1));
            // First bit of header is the ADPCM flag 1 = ADPCM, 0 = PCM
            // The rest is the sample rate in kHz
            adpcmCompression = (header & 0b10000000) > 0;
            sampleRate = (header & 0b01111111) * 1000;

            let audioData;
            if (adpcmCompression) {
                audioData = decodeADPCM8Bit(body);
            } else {
                audioData = new Int16Array(body.buffer);
            }

            const float32Array = new Float32Array(audioData.length);
            for (let i = 0; i < audioData.length; i++) {
                float32Array[i] = audioData[i] / 32768;
            }

            updateVisualizer(float32Array);
            processAudioData(float32Array);
        }
    };
}

// Update the window.addEventListener('load') to just call initializeWebSocket
window.addEventListener('load', initializeWebSocket);

playButton.addEventListener('click', () => {
    if (!audioContext) {
        startStream();
    } else {
        stopStream();
    }
});

function startStream() {
    if (!audioContext) {
        const audioContextOptions = {
            sampleRate: 44100,
            latencyHint: 'interactive'
        };

        audioContext = new (window.AudioContext || window.webkitAudioContext)(audioContextOptions);

        if (audioContext.state === 'suspended' && 'ontouchstart' in window) {
            audioContext.resume();
        }

        console.log('Audio context sample rate:', audioContext.sampleRate);
        isPlaying = true;
        webSocket.send('play'); // Send play message
        playButton.innerHTML = '<img src="stop.png" alt="Stop" width="64" height="64">';
        // statusMessage.innerHTML = 'Audio playing <span style="font-size: 24px;">&#128266;</span>';
        updateStatusMessage();
    } else {
        stopStream();
    }
}

function stopStream() {
    if (audioContext) {
        audioContext.close();
        audioContext = null;
    }
    if (webSocket && webSocket.readyState === WebSocket.OPEN) {
        webSocket.send('stop'); // Send stop message only if connection is open
    }
    isPlaying = false;
    scheduledTime = 0;
    playButton.innerHTML = '<img src="play.png" alt="Play" width="64" height="64">';
    statusMessage.textContent = 'Click to start audio';
    statusMessage.className = '';
    updateStatusMessage();
    resetVisualizer();
}

function updateStatusMessage() {
    if (!audioContext) {
        statusMessage.textContent = 'Click to start audio';
        statusMessage.className = '';
    } else if (micStatus === 'mic_active') {
        statusMessage.innerHTML = 'Audio playing <span style="font-size: 24px;">&#128266;</span>';
        statusMessage.className = 'playing';
    } else {
        statusMessage.innerHTML = 'Sender is muted <span style="font-size: 24px;">&#128263;</span>';
        statusMessage.className = 'muted';
    }
}

let showStats = false;
let audioGaps = [];
let bufferTrend = 'stable';
const GAPS_WINDOW = 60000; // 1 minute in milliseconds

function processAudioData(float32Array) {
    const currentTime = audioContext.currentTime;
    let playbackTime = Math.max(currentTime, scheduledTime);

    // Check for gaps
    if (scheduledTime > 0 && currentTime > scheduledTime + 0.01) { // Gap larger than 10ms
        audioGaps.push({
            time: Date.now(),
            duration: currentTime - scheduledTime
        });
    }

    // Clean up old gaps
    const now = Date.now();
    audioGaps = audioGaps.filter(gap => now - gap.time < GAPS_WINDOW);

    const resampledArray = resampleAudioData(float32Array, sampleRate, audioContext.sampleRate);
    const audioBuffer = audioContext.createBuffer(1, resampledArray.length, audioContext.sampleRate);
    audioBuffer.getChannelData(0).set(resampledArray);

    const bufferSource = audioContext.createBufferSource();
    bufferSource.buffer = audioBuffer;
    bufferSource.connect(audioContext.destination);

    // Calculate buffer latency
    bufferLatency = playbackTime - currentTime;
    meanBufferLatency = meanBufferLatency * MEAN_BUFFER_LATENCY_EMA_FACTOR + bufferLatency * (1 - MEAN_BUFFER_LATENCY_EMA_FACTOR);

    const fastRate = 1.02;
    const slowRate = 0.98;


    // Adjust playback rate based on buffer latency
    if (meanBufferLatency > targetBufferDuration + 0.15 || (bufferTrend === 'decreasing' && meanBufferLatency > targetBufferDuration)) {
        // Ahead of target, speed up slightly
        bufferSource.playbackRate.value = fastRate;
        bufferTrend = 'decreasing';
    } else if (meanBufferLatency < targetBufferDuration - 0.05 || (bufferTrend === 'increasing' && meanBufferLatency < targetBufferDuration)) {
        // Behind target, slow down slightly
        bufferSource.playbackRate.value = slowRate;
        bufferTrend = 'increasing';
    } else {
        // Within acceptable range
        bufferSource.playbackRate.value = 1.0;
        bufferTrend = 'stable';
    }

    bufferSource.start(playbackTime);
    scheduledTime = playbackTime + (audioBuffer.duration / bufferSource.playbackRate.value);
}

function updateStatistics() {
    if (!showStats) return;

    const stats = document.getElementById('statistics');

    // Use pre-calculated values from websocket onmessage
    const trendText = {
        'increasing': 'increasing',
        'decreasing': 'decreasing',
        'stable': 'stable\u00A0\u00A0\u00A0\u00A0'  // using non-breaking spaces
    }[bufferTrend];

    stats.innerHTML = `Buffer: ${Math.round(meanBufferLatency * 1000)}ms (${trendText}) | ` +
        `Recommended: ${Math.round(recommendedBuffer * 1000)}ms | ` +
        `Target: ${Math.round(targetBufferDuration * 1000)}ms | ` +
        `Std Dev: ${Math.round(stdDeviation)}ms | ` +  // using pre-calculated value
        `Gaps: ${audioGaps.length} in last minute | ` +
        `Click to hide statistics`;
}

document.getElementById('statistics').addEventListener('click', () => {
    showStats = !showStats;
    const stats = document.getElementById('statistics');
    if (!showStats) {
        stats.textContent = 'Click to show statistics';
    } else {
        updateStatistics();
    }
});

setInterval(updateStatistics, 50);  // Changed to 500ms

function updateVisualizer(newData) {
    visualizerData = new Float32Array([...visualizerData.slice(newData.length), ...newData]);
    drawWaveform();
}

function resetVisualizer() {
    visualizerData.fill(0);
    drawWaveform();
}

function drawWaveform() {
    visualizerContext.clearRect(0, 0, visualizer.width, visualizer.height);
    visualizerContext.beginPath();
    visualizerContext.strokeStyle = '#3498db';
    visualizerContext.lineWidth = 2;

    const sliceWidth = visualizer.width / visualizerData.length;
    for (let i = 0; i < visualizerData.length; i++) {
        const x = i * sliceWidth;
        const y = (visualizerData[i] + 1) * visualizer.height / 2;

        if (i === 0) {
            visualizerContext.moveTo(x, y);
        } else {
            visualizerContext.lineTo(x, y);
        }
    }

    visualizerContext.stroke();
}

// Initial draw of the waveform
drawWaveform();

// Clean up intervals when the page is unloaded
window.addEventListener('beforeunload', () => {
    if (heartbeatCheckInterval) {
        clearInterval(heartbeatCheckInterval);
    }
    if (reconnectInterval) {
        clearInterval(reconnectInterval);
    }
}); 