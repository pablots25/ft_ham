# FT Ham

An iOS application for FT8/FT4 digital amateur radio communication. FT Ham enables amateur radio operators to encode, transmit, receive, and decode FT8/FT4 signals with support for logbook management and real-time spectrum analysis.

## Features

- **FT8/FT4 Encoding & Decoding**: Full support for FT8 and FT4 digital modes
- **Audio Processing**: Real-time FFT analysis and GFSK signal synthesis
- **Logbook Management**: Record and manage QSO (contact) logs in ADIF format
- **Spectrum Analysis**: Visual frequency monitoring and signal detection
- **Message Composer**: Build and transmit FT8/FT4 messages with standard callsign formats

## For More Information

Visit the [FT Ham Landing Page](https://ftham.turrion.dev/) for:
- Detailed app documentation
- Quick start guides
- Feature overview
- Support and contact information

## License

This project is licensed under the **MIT License** – see [Resources/Licenses/Licenses.txt](Resources/Licenses/Licenses.txt) for full details.

### Core Application
Copyright © 2026 Pablo Turrión San Pedro (EA4IQL)

### Third-Party Libraries
- **ft8_lib**: Copyright (c) 2018-2025 kgoba (MIT License)
- **KISS FFT**: Copyright (c) 2003-2010 Mark Borgerding (BSD-3-Clause)
- **Firebase iOS SDK**: Copyright 2011-2026 Google Inc. (Apache License 2.0)

## Disclaimer

This application is provided **"as-is"** without warranties of any kind. The authors are not responsible for:

- Any regulatory violations in your jurisdiction
- Interference with other communications
- Data loss or corruption
- Misuse of exported data files
- Third-party service interruptions (Firebase, etc.)

Users are solely responsible for complying with local amateur radio regulations and licensing requirements.

### Privacy

- Anonymous usage analytics are collected via Firebase Analytics
- **No personal data is stored or shared** with third parties
- Users can disable analytics in app settings
- Exported ADIF logs and data files are under user control

## Building & Contributing

To build from source:

1. Clone the repository
2. Open `ft8_ham.xcodeproj` in Xcode
3. Configure signing certificates for your Apple developer account
4. Build and run on an iOS device

### Code Structure

```
ft_ham/
├── ft8_manager/          # FT8/FT4 encoding/decoding engine (C/C++)
│   └── ft8_lib/         # Third-party ft8_lib implementation
├── Models/              # Swift data models & business logic
├── Views/               # SwiftUI interface components
├── Utils/               # Utility functions & helpers
└── Resources/           # Assets & license files
```

## Contact & Support

**Author**: Pablo Turrión San Pedro (EA4IQL)  
**Email**: ea4iql@turrion.dev  

For issues, feature requests, or questions about licensing, please open an issue on GitHub.

---

**Last Updated**: January 2026
