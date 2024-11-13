# Local Audio Streaming App for Live Translation

This mobile app enables real-time audio streaming over a local network, designed especially for live translation services in settings like churches or small events. The app allows a translator to broadcast audio from their device’s microphone to listeners connected on the same network. Users can access the stream through a browser on any device connected to the network.

## Features

- **Real-Time Audio Streaming**: Transmits live audio from the translator to listeners over a local Wi-Fi network.
- **Simple Network Setup**: Listeners can join the stream without any login or complex configuration.
- **Adjustable Audio Quality**: Choose from various bitrate options (8, 16, 32, 64, 128 kbps) to balance audio quality and network load.
- **Local Network Only**: Audio is streamed only within the local network, ensuring privacy and low latency.
- **No Data Collection**: The app does not store or transmit any data beyond the local network. It only accesses the microphone for its core functionality.

## Technologies

- **Flutter** for cross-platform development (Android and iOS).
- **WebSocket** for low-latency, bidirectional data transmission.
- **PCM Audio Data** to maintain audio quality and compatibility across platforms.

## Requirements

- **Flutter** (version X.X.X)
- A device running Android or iOS on the same local network as listener devices

## Getting Started

### Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/Jorineg/audio_live_stream.git
   cd audio_live_stream
   ```
2. Install dependencies:
   ```bash
   flutter pub get
   ```
3. Run the app on a connected device:
   ```bash
   flutter run
   ```

### Usage

1. Open the app and grant microphone permissions when prompted.
2. Start the server within the app to begin streaming.
3. Share the local IP address or scan the QR code (provided in-app) to allow listeners to connect via a browser on the same network.
4. Adjust bitrate settings as needed to optimize for network conditions.

### Listener Instructions

Listeners can join the audio stream by entering the IP address in a browser or scanning the QR code provided by the translator. Make sure all devices are connected to the same local network.

## Privacy Policy

This app does not collect, store, or share any personal data or information. The microphone data is streamed within the local network only and is not shared with any external servers or third parties. 

For more details, see the full privacy policy [here](PRIVACY_POLICY.md).

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please open an issue or submit a pull request for any features, bug fixes, or enhancements.