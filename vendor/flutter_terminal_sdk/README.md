
# **Flutter TerminalSDK Documentation**

The `TerminalSDK` library provides a set of classes and methods for handling user authentication, terminal connections, and card transactions.

### Step 1: Google Play Integrity and Huawei Safety Detect

This library uses Google Play Integrity (Mandatory) and Huawei Safety Detect (Optional) to verify the integrity of the device.

### Google Play Integrity (Mandatory)

To make the library work, you need to have a Google Cloud project with Play Integrity enabled and pass the Google Cloud project number in the builder. Here are the steps to do so:

**Create a Google Cloud Project:**

- Go to the [Google Cloud Console](https://console.cloud.google.com/).
  - Create a new project or use an existing one.

**Get the Project Number:**

- Go to the [Google Cloud Console](https://console.cloud.google.com/).
- Click on the project you created.
- Go to the project settings.
- Copy the project number.

**Enable Play Integrity API:**

- Go to the [Google Play Console](https://play.google.com/console/).
- Navigate to Release > App Integrity.
- Under the Play Integrity API, select Link a Cloud project.
- Choose the Cloud project you want to link to your app, which will enable Play Integrity API responses.
- This may change in the future, so please refer to the official documentation here: [Google Play Integrity documentation](https://developer.android.com/google/play/integrity/setup)

**Pass the Project Number in the Builder:**

- Use the `googleCloudProjectNumber` method in the builder to pass the project number.

### Huawei Safety Detect (Optional)

To use Huawei Safety Detect, you need to have a Huawei Developer account and pass the Safety Detect API key in the builder. Here are the steps to do so:

**Create a Huawei Developer Account:**

- Go to the [Huawei Developer Console](https://developer.huawei.com/consumer/en/console).
- Create a new account or use an existing one.

**Create an App:**

- Go to AppGallery Connect.
- Create a new app or use an existing one.

**Enable Safety Detect:**

- Go to the AppGallery Connect console.
- Navigate to Develop > Security Detection.
- Enable Safety Detect.

**Get the Safety Detect API Key:**

- Go to the AppGallery Connect console.
- Navigate to Develop > Security Detection.
- Click on the Safety Detect tab.
- Copy the API key.

**Pass the API Key in the Builder:**

- Use the `safetyDetectApiKey` method in the builder to pass the Safety Detect API key.

### Configuring the Secure Maven Repository / Dependencies

For the ReaderCore library, you can include the following configuration in your root-level `build.gradle` file:

```kotlin
allprojects {
    repositories {
        def props = new Properties()
        maven {
            url = "https://gitlab.com/api/v4/projects/37026421/packages/maven"
            credentials(HttpHeaderCredentials) {
                name = 'Private-Token'
                value = "ADD_YOUR_TOKEN_HERE"
            }
            authentication {
                header(HttpHeaderAuthentication)
            }
        }

        maven { url 'https://jitpack.io' }
        maven { url 'https://developer.huawei.com/repo/' }
    }
}
```

In addition, you have to change the `minSdk` version to 28 and the `versionName` to 75 in your `build.gradle` file:

### Kotlin

```kotlin
android {
    defaultConfig {
        minSdk = 28
        versionName = "75"
    }
}
```

Contact Nearpay to register your `applicationId` and get the necessary credentials.

### AndroidManifest.xml Configuration

In your `AndroidManifest.xml` file, add the following line:

```xml
<application android:allowBackup="true"
    tools:replace="android:allowBackup" /> <!-- Add this line to avoid manifest merger issues -->
```

### Step 2: Add the dependencies to your `pubspec.yaml` file: (Very Important)

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_terminal_sdk:
    # The example app is bundled with the plugin so we use a path dependency on
    # the parent directory to use the current plugin's version.
    
    # Replace this with the actual path to the plugin on your machine.
    path: ../ # Path to the plugin
```


## Part 2: **Getting Started with TerminalSDK**

To start using `TerminalSDK`, initialize it with the necessary configurations.

### Dart

```dart
// initializing the terminalSDK may throw an exception, so wrap it in a try-catch block
final FlutterTerminalSdk _terminalSdk = FlutterTerminalSdk();
await _terminalSdk.initialize(
  environment: Environment.sandbox,
  googleCloudProjectNumber: 12345678L, // Add your google cloud project number
  huaweiSafetyDetectApiKey: "your_api_key", // Add your huawei safety detect api key
  country: Country.tr
);
```

## Part 3: **Authentication**

### **Send OTP**

The SDK supports both mobile and email OTP authentication.

#### Mobile Authentication

#### Dart

```dart
await _terminalSdk.sendMobileOtp(mobile);
```

#### Email Authentication

#### Dart

```dart
await _terminalSdk.sendEmailOtp(email);
```

### **Verify OTP**

After sending the OTP, verify it to authenticate the user.

#### Mobile Verification

#### Dart

```dart
final user = await _terminalSdk.verifyMobileOtp(
  mobileNumber: mobile,
  code: code,
);
```

#### Email Verification

#### Dart

```dart
final user = await _terminalSdk.verifyEmailOtp(
  email: email,
  code: code,
);
```

#### JWT Verification

#### Dart

```dart
final terminalModel = await _terminalSdk.jwtLogin(
  jwt: jwt,
);
```

### **Get User**

You can also get a User instance after calling the getUserByUUID method if the user has already been authenticated before using the SDK and you have their UUID from the previously returned User instance.

> Saving the user UUID is the responsibility of the developer, not the SDK.

#### Dart

```dart
final user = await _terminalSdk.getUser(
  uuid: _verifiedUser!.userUUID!,
);
```

### **Get List of Users**

You can also get a List of User after calling the getUsers method and will return a list of authenticated users.

#### Dart

```dart
final listOfUsers = await _terminalSdk.getUsers();
```

### **Logout User**

To log out a user and delete its instance from memory, call the logout method.

Takes a User UUID as a parameter and logs out the user.

#### Dart

```dart
await _terminalSdk.logout(
  uuid: _verifiedUser!.userUUID!,
);
```

## **Part 4: User Operations**

The User class is initialized internally by the SDK and provides methods for managing terminals.

### **List Terminals**

Retrieves a paginated list of terminals associated with the user.

#### Usage

#### Dart

```dart
final fetchedTerminals = await _terminalSdk.getTerminalList(
  _verifiedUser!.userUUID!,
  page: 1,
  pageSize: 10
);
```

## **Part 5: Terminal Connection Operations**

### **Connect Terminal**

Establishes a connection with a terminal.

#### Usage

#### Dart

```dart
final connectedTerminal = await _terminalSdk.connectTerminal(
  tid: terminal.tid,
  userUUID: terminal.userUUID,
  terminalUUID: terminal.uuid,
);
```

## **Part 6: Terminal Operations**

Before getting into Terminal class functions, you can also get a Terminal instance after calling the getTerminal method and passing the terminal's ID instead of using a TerminalConnection instance.

### **Get Terminal**

Retrieves a Terminal instance for a specific terminal ID.

#### Dart

```dart
final fetchedTerminal = await _terminalSdk.getTerminal(
  tid: 'your tid number',
);
```

### Purchase

Initiates a purchase transaction by reading the card and sending the transaction.

#### Dart

```dart
try {
  setState(() => _status = "Purchasing...");

  // Define the callbacks for purchase events
  final callbacks = PurchaseCallbacks(
    cardReaderCallbacks: CardReaderCallbacks(
      onReadingStarted: () {
        setState(() => _status = "Reading started...");
      },
      onReaderWaiting: () {
        setState(() => _status = "Reader waiting...");
      },
      onReaderReading: () {
        setState(() => _status = "Reader reading...");
      },
      onReaderRetry: () {
        setState(() => _status = "Reader retrying...");
      },
      onPinEntering: () {
        setState(() => _status = "Entering PIN...");
      },
      onReaderFinished: () {
        setState(() => _status = "Reader finished.");
      },
      onReaderError: (message) {
        setState(() => _status = "Reader error: $message");
      },
      onCardReadSuccess: () {
        setState(() => _status = "Card read successfully.");
      },
      onCardReadFailure: (message) {
        setState(() => _status = "Card read failure: $message");
      },
    ),
    onSendTransactionFailure: (message) {
      setState(() => _status = "Transaction failed: $message");
    },
    onSendTransactionSuccessData: (tr.TransactionResponse response) {
      setState(() => _status = "Purchase Successful!");
      _showTransactionDialog(response);
    },
  );

  transactionUuid = const Uuid().v4(); // Generate a unique transaction UUID for the purchase, this is developer's responsibility

  final purchaseResponse = await _connectedTerminal!.purchase(
    amount: amount,
    scheme: scheme,
    callbacks: callbacks,
    transactionUuid: transactionUuid!,
  );

  print("Purchase Response: $purchaseResponse");
} catch (e) {
  setState(() => _status = "Error in purchase: $e");
}
```

### **Refund**

Initiates a refund transaction by reading the card and sending the transaction.

#### Dart

```dart
try {
  var callback = RefundCallbacks(
    cardReaderCallbacks: CardReaderCallbacks(
      onReadingStarted: () {
        setState(() => _status = "Reading started...");
      },
      onReaderWaiting: () {
        setState(() => _status = "Reader waiting...");
      },
      onReaderReading: () {
        setState(() => _status = "Reader reading...");
      },
      onReaderRetry: () {
        setState(() => _status = "Reader retrying...");
      },
      onPinEntering: () {
        setState(() => _status = "Entering PIN...");
      },
      onReaderFinished: () {
        setState(() => _status = "Reader finished.");
      },
      onReaderError: (message) {
        setState(() => _status = "Reader error: $message");
      },
      onCardReadSuccess: () {
        setState(() => _status = "Card read successfully.");
      },
      onCardReadFailure: (message) {
        setState(() => _status = "Card read failure: $message");
      },
    ),
    onSendTransactionSuccess: (response) {
      setState(() => _status = "Refund Successful!");
      _showTransactionDialog(response);
    },
    onSendTransactionFailure: (message) {
      setState(() => _status = "Refund failed: $message");
    },
  );

  var refundUuid = const Uuid().v4(); // Generate a unique refund UUID for the refund, this is developer's responsibility

  setState(() => _status = "Refunding...");
  final result = await _connectedTerminal?.refund(
    refundUuid: refundUuid,
    transactionUuid: transactionUuid!,
    amount: amount,
    scheme: _selectedScheme,
    callbacks: callback,
  );

  setState(() => _status = "Refund Successful: ${result.toString()}");
} catch (e) {
  setState(() => _status = "Error in refund: $e");
}
```

### **Get Transaction Details**

Retrieves the details of a specific transaction by providing the transaction ID.

#### Dart

```dart
final transactionDetails = await _connectedTerminal?.getTransactionDetails(
  transactionUuid: "your-transaction-uuid",
);
```

### **Get Transactions List**

Retrieves a paginated list of transactions.

#### Dart

```dart
final transactionList = await _connectedTerminal?.getTransactionList(
  page: 1,
  pageSize: 10,
);
```

### **Reconcile Transactions**

Reconciles a terminal's unreconciled transactions.

#### Dart

```dart
await _connectedTerminal?.reconcile();
```

### **Get Reconciliation List**

Retrieves a paginated list of reconciliations.

#### Dart

```dart
final reconciliationList = await _connectedTerminal?.getReconcileList(
  page: 1,
  pageSize: 10,
);
```

### **Get Reconciliation Details**

Retrieves the details of a specific reconciliation by providing the reconciliation ID.

#### Dart

```dart
final reconcileDetails = await _connectedTerminal?.getReconcileDetails(
  uuid: reconcileId ?? "",
);
```

### **Reverse**

Reverses a transaction by providing the transaction ID.

#### Dart

```dart
final reverseResponse = await _connectedTerminal!.reverse(
  transitionId: transactionUuid!,
);
```

### **Cancel**

Cancels a transaction by providing the transaction ID.

#### Dart

```dart
final cancelResponse = await _connectedTerminal!.cancel(
  transactionUUID: transactionUuid!,
);
```
```