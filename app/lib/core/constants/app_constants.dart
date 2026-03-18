/// App-wide constants: routes, limits, copy.
class AppConstants {
  AppConstants._();

  // ——— Brand ———
  static const String appName = 'Crossed';
  static const String logoAsset = 'assets/logo.svg';
  static const String tagline = 'Meaningful connections, designed for real life';

  // Routes (used with go_router)
  static const String routeSplash = '/';
  static const String routeOnboarding = '/onboarding';
  static const String routeAuth = '/auth';
  static const String routeRegister = '/register';
  static const String routeProfileSetup = '/profile-setup';
  static const String routeKyc = '/kyc';
  static const String routeHome = '/home';
  static const String routeDiscovery = '/discovery';
  static const String routeMatches = '/matches';
  static const String routeChat = '/chat/:matchId';
  static const String routeProfile = '/profile';
  static const String routeSettings = '/settings';
  static const String routeRooms = '/rooms';
  static const String routeCreateRoom = '/rooms/create';
  static const String routeRoomDetail = '/rooms/:roomId';
  static String routeRoomDetailWithId(String roomId) => '/rooms/$roomId';

  /// Backend API base URL. Production: Render; local: 10.0.2.2 (Android emulator), localhost (iOS simulator).
  static const String apiBaseUrl = 'https://dating-app-backend-nn8o.onrender.com';

  // Discovery
  static const int maxDailyLikes = 50; // Reduce endless swiping
  static const int maxPhotosPerProfile = 6;
  static const int minPhotosRequired = 2;
  static const int maxPromptAnswers = 3;
  static const int maxBioLength = 500;

  // Safety
  static const int reportReasonsCount = 6;
  static const List<String> reportReasons = [
    'Inappropriate content',
    'Harassment or bullying',
    'Fake profile or scam',
    'Hate speech or symbols',
    'Violence or threats',
    'Other',
  ];

  // Opening moves (Bumble-style)
  static const List<String> defaultOpeningMoves = [
    "What's your ideal first date?",
    "What's the best trip you've ever taken?",
    "What's something you're passionate about?",
    "Coffee or tea? (This matters.)",
    "What's your go-to karaoke song?",
    "What's the last thing that made you laugh really hard?",
  ];

  // Hinge-style prompts for profile
  static const List<String> profilePrompts = [
    'I\'m looking for...',
    'Together we could...',
    'I\'ll fall for you if...',
    'A life goal of mine...',
    'I\'m convinced that...',
    'The way to win me over...',
    'My simple pleasures...',
    'We\'re the same type of weird if...',
    'I\'ll know I\'ve found the one when...',
    'The key to my heart is...',
  ];

  // Rooms — experience-based activities
  static const String roomTypePersonal = 'personal';
  static const String roomTypeGroup = 'group';

  /// Activity types for room creation (id, label, emoji)
  static const List<Map<String, String>> roomActivityTypes = [
    {'id': 'cafe', 'label': 'Cafe Date', 'emoji': '☕'},
    {'id': 'dinner', 'label': 'Dinner Table', 'emoji': '🍽'},
    {'id': 'hiking', 'label': 'Adventure', 'emoji': '🥾'},
    {'id': 'movie', 'label': 'Movie Night', 'emoji': '🎬'},
    {'id': 'camping', 'label': 'Camping', 'emoji': '🏕'},
    {'id': 'games', 'label': 'Fun Activity', 'emoji': '🎮'},
    {'id': 'travel', 'label': 'Travel Buddy', 'emoji': '✈️'},
    {'id': 'skill', 'label': 'Skill Room', 'emoji': '🧠'},
  ];

  static const List<String> roomTagSuggestions = [
    'Adventure',
    'Casual',
    'Food',
    'Travel',
    'Weekend',
    'Chill',
    'Outdoor',
    'Creative',
  ];

  // Onboarding / KYC: gender selected during onboarding, verified against selfie
  static const List<String> onboardingGenders = ['Male', 'Female', 'Non-binary', 'Prefer not to say'];

  // Relationship goals
  static const List<String> relationshipGoals = [
    "Long-term relationship",
    "Short-term fun",
    "New friends",
    "Not sure yet",
    "Life partner",
  ];
}
