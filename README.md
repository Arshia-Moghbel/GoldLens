# GoldLens
📈 Gold Investing

<p align="center">
  <img src="Screenshots/app-icon.png" width="120" alt="Gold Investing Logo">
</p>
<p align="center">
  <strong>An elegant iOS application for real-time Gold & Currency tracking with AI-powered market analysis.</strong>
</p>
<p align="center">
</p>

⸻

✨ Overview

Gold Investing is a modern native iOS application designed to help users monitor gold and foreign exchange markets with an intuitive interface, real-time data, and intelligent market insights.

The goal is to provide fast, reliable, and user-friendly financial information while keeping the interface clean and beautiful.

⸻

📱 Screenshots

Home	Chart
	
AI Analysis	Watchlist
	

⸻

🚀 Features

* 📈 Live Gold Prices
* 💵 Live Currency Exchange Rates
* 📊 Interactive Charts
* 🤖 AI Market Analysis
* 🔔 Price Alerts
* ⭐ Favorites
* 📉 Historical Data
* 🌙 Dark Mode
* ⚡ Native Performance
* 🔍 Powerful Search

⸻

🏗 Architecture

The application follows the MVVM (Model-View-ViewModel) architecture.

View
 │
 ▼
ViewModel
 │
 ▼
Repository
 │
 ▼
Network Layer
 │
 ▼
REST API

Advantages

* Clean Architecture
* Testable
* Scalable
* Easy Maintenance
* Reusable Components

⸻

📂 Project Structure

GoldInvesting/
├── App/
│
├── Models/
│
├── Views/
│
├── ViewModels/
│
├── Services/
│
├── Networking/
│
├── Components/
│
├── Extensions/
│
├── Resources/
│
├── Assets.xcassets/
│
├── Utilities/
│
└── SupportingFiles/

⸻

🌐 API

Example REST endpoint:

GET /gold/latest
GET /currency/latest
GET /analysis

Expected Response

{
    "gold_price": 7245000,
    "usd_price": 93400,
    "change": 1.82,
    "trend": "bullish"
}

⸻

⚙️ Technologies

* Swift 6
* SwiftUI
* MVVM
* URLSession
* Async/Await
* Codable
* REST API
* JSON
* Combine
* Charts

⸻

📦 Installation

Clone the repository

git clone https://github.com/yourusername/GoldInvesting.git

Go to the project

cd GoldInvesting

Open in Xcode

GoldInvesting.xcodeproj

Run the application.

⸻

📋 Roadmap

* ✅ Live Gold Prices
* ✅ Live Currency Prices
* ✅ Data-driven market analysis
* ✅ Price notifications
* ✅ Portfolio tracking
* ⏳ Apple Watch companion — requires a paired Apple Watch for on-device delivery and validation
* ✅ Home Screen widgets and Live Activities
* ✅ iPad support
* ✅ Persian and English interface
* ✅ Offline last-known-price mode

⸻

📊 Performance Goals

* Native iOS Performance
* Fast Network Requests
* Smooth Animations
* Battery Efficient
* Lightweight UI

⸻

🧪 Testing

Unit Tests
UI Tests
Integration Tests

⸻

🤝 Contributing

Contributions are welcome.

1. Fork the repository
2. Create your feature branch
3. Commit your changes
4. Push to your branch
5. Open a Pull Request

⸻

📄 License

This project is licensed under the MIT License.

⸻

👨‍💻 Author

Arshia Moghbel

Swift Developer • iOS Enthusiast • AI & FinTech

GitHub:

https://github.com/Arshia-Moghbel

⸻

<p align="center">

Made with ❤️ using SwiftUI

</p>
