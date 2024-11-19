function decodeADPCM8Bit(adpcmData) {
    // Ensure adpcmData is a Uint8Array
    if (!(adpcmData instanceof Uint8Array)) {
        adpcmData = new Uint8Array(adpcmData);
    }

    // Extract prevSample and index from the packet header
    const headerView = new DataView(adpcmData.buffer, adpcmData.byteOffset, 4);
    let prevSample = headerView.getInt16(0, true); // Little-endian
    let index = headerView.getUint8(2);
    // Skip the blank byte at headerView.getUint8(3);

    // Extract the encoded data
    const data = adpcmData.slice(4);
    const len = data.length * 2; // Each byte contains two samples
    const int16Array = new Int16Array(len);

    // Step size table (standard IMA ADPCM table with 89 entries)
    const stepSizeTable = [
        7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31,
        34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130, 143,
        157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544,
        598, 658, 724, 796, 876, 963, 1060, 1166, 1282, 1411, 1552, 1707,
        1878, 2066, 2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871,
        5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635,
        13899, 15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767
    ];

    // Index table for ADPCM
    const indexTable = [-1, -1, -1, -1, 2, 4, 6, 8];

    for (let n = 0; n < data.length; n++) {
        const byte = data[n];
        // Extract two 4-bit codes
        const codeHigh = (byte >> 4) & 0x0F; // High nibble
        const codeLow = byte & 0x0F;         // Low nibble

        // Decode first sample
        let code = codeHigh;
        let step = stepSizeTable[index];
        let diffq = 0;

        let sign = code & 8;
        code = code & 7;

        if (code & 4) diffq += step;
        if (code & 2) diffq += step >> 1;
        if (code & 1) diffq += step >> 2;
        diffq += step >> 3;

        if (sign)
            prevSample -= diffq;
        else
            prevSample += diffq;

        // Clamp prevSample
        if (prevSample > 32767)
            prevSample = 32767;
        else if (prevSample < -32768)
            prevSample = -32768;

        int16Array[n * 2] = prevSample;

        // Update index
        index += indexTable[code];
        if (index < 0)
            index = 0;
        else if (index > 88)
            index = 88;

        // Decode second sample
        code = codeLow;
        step = stepSizeTable[index];
        diffq = 0;

        sign = code & 8;
        code = code & 7;

        if (code & 4) diffq += step;
        if (code & 2) diffq += step >> 1;
        if (code & 1) diffq += step >> 2;
        diffq += step >> 3;

        if (sign)
            prevSample -= diffq;
        else
            prevSample += diffq;

        // Clamp prevSample
        if (prevSample > 32767)
            prevSample = 32767;
        else if (prevSample < -32768)
            prevSample = -32768;

        int16Array[n * 2 + 1] = prevSample;

        // Update index
        index += indexTable[code];
        if (index < 0)
            index = 0;
        else if (index > 88)
            index = 88;
    }

    return int16Array;
}

function resampleAudioData(inputArray, inputSampleRate, outputSampleRate) {
    if (inputSampleRate === outputSampleRate) {
        return inputArray;
    }

    const sampleRateRatio = outputSampleRate / inputSampleRate;
    const newLength = Math.round(inputArray.length * sampleRateRatio);
    const outputArray = new Float32Array(newLength);

    for (let i = 0; i < newLength; i++) {
        const idx = i / sampleRateRatio;
        const idx_low = Math.floor(idx);
        const idx_high = Math.min(idx_low + 1, inputArray.length - 1);
        const weight = idx - idx_low;
        outputArray[i] = (1 - weight) * inputArray[idx_low] + weight * inputArray[idx_high];
    }
    return outputArray;
}

export { decodeADPCM8Bit, resampleAudioData }; 