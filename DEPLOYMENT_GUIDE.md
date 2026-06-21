# CaddyMoney - Deployment & Setup Guide

## Overview

CaddyMoney is a comprehensive multi-role fintech platform built with Flutter and Supabase. It supports three distinct user roles:
- **Standard Users**: Send and receive money
- **Merchants**: Register businesses and receive payments
- **Platform Administrators**: Manage users, merchants, and transactions

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Supabase Setup](#supabase-setup)
3. [Database Schema Deployment](#database-schema-deployment)
4. [Flutter Configuration](#flutter-configuration)
5. [Creating Admin Accounts](#creating-admin-accounts)
6. [Localization](#localization)
7. [Testing the Application](#testing-the-application)
8. [Extension Guide](#extension-guide)

---

## Prerequisites

- Flutter SDK 3.6.0 or higher
- Dart 3.6.0 or higher
- A Supabase account (free tier works fine)
- Android Studio / VS Code with Flutter extensions
- Android/iOS device or emulator for testing

---

## Supabase Setup

### Step 1: Create a Supabase Project

1. Go to [https://supabase.com](https://supabase.com)
2. Sign in or create an account
3. Click "New Project"
4. Fill in the project details:
   - **Name**: CaddyMoney
   - **Database Password**: Choose a strong password (save this!)
   - **Region**: Choose closest to your users
   - **Pricing Plan**: Free (or Pro if needed)
5. Wait for the project to be created (1-2 minutes)

### Step 2: Get API Credentials

1. In your Supabase project dashboard, go to **Settings** → **API**
2. Copy the following:
   - **Project URL** (e.g., `https://xxxxx.supabase.co`)
   - **Anon/Public Key** (starts with `eyJ...`)

⚠️ **IMPORTANT**: Never expose the `service_role` key in your Flutter app. It should only be used server-side.

---

## Database Schema Deployment

### Step 1: Access SQL Editor

1. In your Supabase dashboard, go to **SQL Editor**
2. Click **New Query**

### Step 2: Deploy the Schema

1. Open the `supabase_schema.sql` file from this project
2. Copy the entire contents
3. Paste into the Supabase SQL Editor
4. Click **Run** (or press Ctrl/Cmd + Enter)
5. Wait for execution to complete (should take 5-10 seconds)

### Step 3: Verify Tables

1. Go to **Table Editor** in Supabase
2. You should see these tables:
   - `profiles`
   - `merchants`
   - `wallets`
   - `transactions`
   - `wallet_entries`
   - `merchant_status_history`

### What the Schema Includes

- **Automatic Profile Creation**: When a user signs up via Supabase Auth, a profile is automatically created
- **Automatic Wallet Creation**: Users and merchants automatically get wallets
- **Row Level Security (RLS)**: All tables have proper security policies
- **Atomic Transfers**: Server-side functions for safe money transfers
- **Audit Trails**: Complete transaction history and merchant status changes
- **Unique IDs**: Auto-generated merchant IDs and transaction references

---

## Flutter Configuration

### Step 1: Update Supabase Configuration

1. Open `lib/core/config/supabase_config.dart`
2. Replace the placeholder values:

```dart
class SupabaseConfig {
  static const String supabaseUrl = 'https://YOUR_PROJECT_ID.supabase.co';
  static const String supabaseAnonKey = 'YOUR_ANON_KEY_HERE';
}
```

### Step 2: Install Dependencies

```bash
flutter pub get
```

### Step 3: Run the App

```bash
flutter run
```

---

## Creating Admin Accounts

Admin accounts cannot be created through the mobile app for security reasons. They must be created manually in Supabase.

### Method 1: Via Supabase Dashboard

1. Go to **Authentication** → **Users**
2. Click **Add User**
3. Fill in:
   - **Email**: admin@caddymoney.com
   - **Password**: Choose a strong password
   - **Auto Confirm User**: ✓ (check this)
4. Click **Create User**
5. After creation, go to **Table Editor** → **profiles**
6. Find the admin user's profile
7. Edit the `role` column and change it to `admin`
8. Click **Save**

### Method 2: Via SQL

```sql
-- First, create the auth user (replace with your email/password)
INSERT INTO auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at,
  confirmation_token,
  email_change,
  email_change_token_new,
  recovery_token
) VALUES (
  '00000000-0000-0000-0000-000000000000',
  uuid_generate_v4(),
  'authenticated',
  'authenticated',
  'admin@caddymoney.com',
  crypt('YourStrongPassword123!', gen_salt('bf')),
  NOW(),
  '{"provider":"email","providers":["email"]}',
  '{"full_name":"Platform Admin","role":"admin"}',
  NOW(),
  NOW(),
  '',
  '',
  '',
  ''
);

-- Then update the profile role to admin
UPDATE public.profiles
SET role = 'admin'
WHERE email = 'admin@caddymoney.com';
```

---

## Localization

The app supports 6 languages out of the box:
- **French (fr)** - Default
- **English (en)** - Fallback
- **Spanish (es)**
- **German (de)**
- **Italian (it)**
- **Arabic (ar)** - RTL support included

### Adding More Languages

1. Create a new ARB file in `lib/l10n/`:
   ```
   lib/l10n/app_pt.arb  # For Portuguese, for example
   ```

2. Copy content from `app_en.arb` and translate all strings

3. Add the locale to `lib/core/constants/app_constants.dart`:
   ```dart
   static const List<String> supportedLanguages = [
     'fr', 'en', 'es', 'de', 'it', 'ar', 'pt',  // Add 'pt'
   ];
   ```

4. Add the locale to `lib/main.dart` supported locales:
   ```dart
   supportedLocales: const [
     Locale('fr'), Locale('en'), Locale('es'),
     Locale('de'), Locale('it'), Locale('ar'),
     Locale('pt'),  // Add this
   ],
   ```

5. Run `flutter gen-l10n` or restart the app

---

## Testing the Application

### 1. Test User Flow

1. Launch the app → **Role Selection** screen appears
2. Select "I am a user"
3. Create an account with:
   - Name: John Doe
   - Email: john@example.com
   - Password: Test1234!
4. After signup, you should see the **User Home Screen**
5. Check that:
   - Balance card is displayed
   - Quick actions are visible
   - Recent transactions section appears

### 2. Test Merchant Flow

1. Go back to Role Selection
2. Select "I am a merchant"
3. Register a merchant with:
   - Business Name: Test Store
   - Owner Name: Jane Smith
   - Email: jane@example.com
   - Password: Test1234!
   - Category: Retail
4. After registration, you should see **Merchant Dashboard**
5. Note: Status will be "Pending Approval"

### 3. Test Admin Flow

1. Create an admin account (see [Creating Admin Accounts](#creating-admin-accounts))
2. Go back to Role Selection
3. Select "I manage the platform"
4. Sign in with admin credentials
5. You should see:
   - Platform statistics
   - Pending merchant approvals
   - Quick action buttons

### 4. Test Localization

1. Go to Settings
2. Change language from Français to English
3. Navigate back - UI should update
4. Try other languages
5. For Arabic, verify RTL layout works

---

## Extension Guide

### Adding New Screens

The app uses a modular architecture. Here's how to extend it:

#### Example: Add Send Money Screen

1. Create the screen file:
   ```dart
   // lib/screens/user/send_money_screen.dart
   import 'package:flutter/material.dart';
   
   class SendMoneyScreen extends StatelessWidget {
     const SendMoneyScreen({super.key});
     
     @override
     Widget build(BuildContext context) {
       return Scaffold(
         appBar: AppBar(title: const Text('Send Money')),
         body: // Your UI here
       );
     }
   }
   ```

2. Add route in `lib/nav.dart`:
   ```dart
   GoRoute(
     path: '/send-money',
     name: 'send-money',
     pageBuilder: (context, state) => const NoTransitionPage(
       child: SendMoneyScreen(),
     ),
   ),
   ```

3. Navigate from User Home:
   ```dart
   context.push('/send-money');
   ```

### Adding Data Services

1. Create service file:
   ```dart
   // lib/services/transaction_service.dart
   class TransactionService {
     final SupabaseClient _supabase = Supabase.instance.client;
     
     Future<List<TransactionModel>> getUserTransactions() async {
       final userId = _supabase.auth.currentUser?.id;
       final response = await _supabase
         .from('transactions')
         .select()
         .or('sender_profile_id.eq.$userId,receiver_profile_id.eq.$userId')
         .order('created_at', ascending: false);
       
       return (response as List)
         .map((json) => TransactionModel.fromJson(json))
         .toList();
     }
   }
   ```

2. Create provider:
   ```dart
   // lib/providers/transaction_provider.dart
   class TransactionProvider with ChangeNotifier {
     final TransactionService _service = TransactionService();
     List<TransactionModel> _transactions = [];
     
     Future<void> loadTransactions() async {
       _transactions = await _service.getUserTransactions();
       notifyListeners();
     }
   }
   ```

3. Register in main.dart:
   ```dart
   providers: [
     // ... existing providers
     ChangeNotifierProvider(create: (_) => TransactionProvider()),
   ],
   ```

### Implementing Money Transfers

Use the RPC functions defined in the database:

```dart
// Send money to another user
Future<bool> sendMoneyToUser(String receiverUserId, double amount, String? note) async {
  try {
    final response = await Supabase.instance.client
      .rpc('transfer_user_to_user', params: {
        'receiver_user_id': receiverUserId,
        'transfer_amount': amount,
        'transfer_note': note,
      });
    
    return response['success'] == true;
  } catch (e) {
    debugPrint('Transfer error: $e');
    return false;
  }
}

// Send money to merchant
Future<bool> sendMoneyToMerchant(String merchantId, double amount, String? note) async {
  try {
    final response = await Supabase.instance.client
      .rpc('transfer_user_to_merchant', params: {
        'merchant_unique_id': merchantId,
        'transfer_amount': amount,
        'transfer_note': note,
      });
    
    return response['success'] == true;
  } catch (e) {
    debugPrint('Transfer error: $e');
    return false;
  }
}
```

### Admin Functions (Approve/Reject Merchants)

```dart
// Approve merchant
Future<bool> approveMerchant(String merchantId) async {
  try {
    final adminId = Supabase.instance.client.auth.currentUser?.id;
    
    await Supabase.instance.client
      .from('merchants')
      .update({
        'status': 'approved',
        'approved_by': adminId,
        'approved_at': DateTime.now().toIso8601String(),
      })
      .eq('id', merchantId);
    
    // Create status history record
    await Supabase.instance.client
      .from('merchant_status_history')
      .insert({
        'merchant_id': merchantId,
        'old_status': 'pending',
        'new_status': 'approved',
        'changed_by': adminId,
      });
    
    return true;
  } catch (e) {
    return false;
  }
}
```

---

## Security Best Practices

1. **Never expose service role key** in client code
2. **Always use RPC functions** for financial operations
3. **Validate on server-side** - Never trust client input
4. **Use RLS policies** - Already configured in the schema
5. **Audit everything** - Transaction logs are automatic
6. **Encrypt sensitive data** - Use Supabase encryption features
7. **Rate limiting** - Implement on Supabase Edge Functions

---

## Production Checklist

Before deploying to production:

- [ ] Change all default passwords
- [ ] Update Supabase URL and keys in config
- [ ] Enable 2FA for admin accounts
- [ ] Set up proper error logging (e.g., Sentry)
- [ ] Configure backup strategy in Supabase
- [ ] Test all user flows thoroughly
- [ ] Set up monitoring dashboards
- [ ] Create admin documentation
- [ ] Implement proper transaction limits
- [ ] Add fraud detection rules
- [ ] Configure email templates in Supabase Auth
- [ ] Set up proper CORS policies
- [ ] Enable Supabase realtime (if needed)
- [ ] Configure proper database indexes (already done in schema)

---

## Support & Documentation

For additional help:
- Flutter docs: https://flutter.dev/docs
- Supabase docs: https://supabase.com/docs
- Go Router: https://pub.dev/packages/go_router
- Provider: https://pub.dev/packages/provider

---

## License

This project is built as a demonstration of a fintech platform architecture. Modify as needed for your use case.
