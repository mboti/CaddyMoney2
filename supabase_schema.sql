-- ============================================================================
-- CADDYMONEY SUPABASE DATABASE SCHEMA
-- ============================================================================
-- This schema creates a complete fintech platform with user, merchant, and admin roles
-- with atomic money transfers, RLS policies, and audit trails
-- ============================================================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================================
-- 1. PROFILES TABLE
-- ============================================================================
-- Stores user profiles linked to auth.users
CREATE TABLE public.profiles (
  id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  full_name TEXT NOT NULL,
  email TEXT NOT NULL UNIQUE,
  phone TEXT,
  role TEXT NOT NULL DEFAULT 'standardUser' CHECK (role IN ('standardUser', 'merchant', 'admin')),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'suspended', 'deleted')),
  preferred_language TEXT DEFAULT 'fr',
  avatar_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Create index for performance
CREATE INDEX idx_profiles_email ON public.profiles(email);
CREATE INDEX idx_profiles_role ON public.profiles(role);

-- ============================================================================
-- 2. MERCHANTS TABLE
-- ============================================================================
-- Stores merchant business information
CREATE TABLE public.merchants (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  profile_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  unique_merchant_id TEXT NOT NULL UNIQUE,
  business_name TEXT NOT NULL,
  owner_name TEXT NOT NULL,
  business_email TEXT NOT NULL,
  business_phone TEXT,
  address_line1 TEXT,
  address_line2 TEXT,
  city TEXT,
  postal_code TEXT,
  country_code TEXT,
  business_category TEXT,
  registration_number TEXT,
  tax_number TEXT,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'suspended')),
  approved_by UUID REFERENCES public.profiles(id),
  approved_at TIMESTAMPTZ,
  rejected_reason TEXT,
  suspended_reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Generate unique merchant ID function
CREATE OR REPLACE FUNCTION generate_unique_merchant_id()
RETURNS TEXT AS $$
DECLARE
  new_id TEXT;
  done BOOLEAN;
BEGIN
  done := FALSE;
  WHILE NOT done LOOP
    new_id := 'MCH-' || LPAD(FLOOR(RANDOM() * 1000000)::TEXT, 6, '0');
    IF NOT EXISTS (SELECT 1 FROM public.merchants WHERE unique_merchant_id = new_id) THEN
      done := TRUE;
    END IF;
  END LOOP;
  RETURN new_id;
END;
$$ LANGUAGE plpgsql;

-- Trigger to auto-generate merchant ID
CREATE OR REPLACE FUNCTION set_merchant_id()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.unique_merchant_id IS NULL OR NEW.unique_merchant_id = '' THEN
    NEW.unique_merchant_id := generate_unique_merchant_id();
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER before_insert_merchant
  BEFORE INSERT ON public.merchants
  FOR EACH ROW
  EXECUTE FUNCTION set_merchant_id();

CREATE INDEX idx_merchants_profile_id ON public.merchants(profile_id);
CREATE INDEX idx_merchants_status ON public.merchants(status);
CREATE INDEX idx_merchants_unique_id ON public.merchants(unique_merchant_id);

-- ============================================================================
-- 3. WALLETS TABLE
-- ============================================================================
-- Stores wallet balances for users and merchants
CREATE TABLE public.wallets (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  owner_type TEXT NOT NULL CHECK (owner_type IN ('user', 'merchant')),
  profile_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE,
  currency_code TEXT NOT NULL DEFAULT 'EUR',
  balance DECIMAL(15, 2) NOT NULL DEFAULT 0.00 CHECK (balance >= 0),
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT wallet_owner_check CHECK (
    (owner_type = 'user' AND profile_id IS NOT NULL AND merchant_id IS NULL) OR
    (owner_type = 'merchant' AND merchant_id IS NOT NULL AND profile_id IS NULL)
  )
);

CREATE INDEX idx_wallets_profile_id ON public.wallets(profile_id);
CREATE INDEX idx_wallets_merchant_id ON public.wallets(merchant_id);
CREATE INDEX idx_wallets_owner_type ON public.wallets(owner_type);

-- ============================================================================
-- 4. TRANSACTIONS TABLE
-- ============================================================================
-- Stores all financial transactions
CREATE TABLE public.transactions (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  transaction_reference TEXT NOT NULL UNIQUE,
  sender_profile_id UUID REFERENCES public.profiles(id),
  sender_wallet_id UUID REFERENCES public.wallets(id),
  receiver_profile_id UUID REFERENCES public.profiles(id),
  receiver_merchant_id UUID REFERENCES public.merchants(id),
  receiver_wallet_id UUID REFERENCES public.wallets(id),
  amount DECIMAL(15, 2) NOT NULL CHECK (amount > 0),
  currency_code TEXT NOT NULL DEFAULT 'EUR',
  note TEXT,
  type TEXT NOT NULL CHECK (type IN ('userToUser', 'userToMerchant', 'refund', 'adjustment')),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'failed', 'cancelled')),
  failure_reason TEXT,
  metadata JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at TIMESTAMPTZ
);

-- Generate unique transaction reference
CREATE OR REPLACE FUNCTION generate_transaction_reference()
RETURNS TEXT AS $$
DECLARE
  new_ref TEXT;
  done BOOLEAN;
BEGIN
  done := FALSE;
  WHILE NOT done LOOP
    new_ref := 'TXN-' || TO_CHAR(NOW(), 'YYYYMMDD') || '-' || LPAD(FLOOR(RANDOM() * 100000)::TEXT, 5, '0');
    IF NOT EXISTS (SELECT 1 FROM public.transactions WHERE transaction_reference = new_ref) THEN
      done := TRUE;
    END IF;
  END LOOP;
  RETURN new_ref;
END;
$$ LANGUAGE plpgsql;

CREATE INDEX idx_transactions_sender ON public.transactions(sender_profile_id);
CREATE INDEX idx_transactions_receiver ON public.transactions(receiver_profile_id);
CREATE INDEX idx_transactions_merchant ON public.transactions(receiver_merchant_id);
CREATE INDEX idx_transactions_status ON public.transactions(status);
CREATE INDEX idx_transactions_type ON public.transactions(type);
CREATE INDEX idx_transactions_reference ON public.transactions(transaction_reference);

-- ============================================================================
-- 5. WALLET ENTRIES TABLE (Ledger)
-- ============================================================================
-- Immutable ledger of all wallet balance changes
CREATE TABLE public.wallet_entries (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  wallet_id UUID REFERENCES public.wallets(id) ON DELETE CASCADE NOT NULL,
  transaction_id UUID REFERENCES public.transactions(id),
  entry_type TEXT NOT NULL CHECK (entry_type IN ('debit', 'credit')),
  amount DECIMAL(15, 2) NOT NULL CHECK (amount > 0),
  balance_before DECIMAL(15, 2) NOT NULL,
  balance_after DECIMAL(15, 2) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_wallet_entries_wallet_id ON public.wallet_entries(wallet_id);
CREATE INDEX idx_wallet_entries_transaction_id ON public.wallet_entries(transaction_id);

-- ============================================================================
-- 6. MERCHANT STATUS HISTORY
-- ============================================================================
-- Track all merchant status changes
CREATE TABLE public.merchant_status_history (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
  old_status TEXT NOT NULL,
  new_status TEXT NOT NULL,
  changed_by UUID REFERENCES public.profiles(id) NOT NULL,
  reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_merchant_status_history_merchant ON public.merchant_status_history(merchant_id);

-- ============================================================================
-- 7. UPDATED_AT TRIGGER FUNCTION
-- ============================================================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply to all relevant tables
CREATE TRIGGER update_profiles_updated_at BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_merchants_updated_at BEFORE UPDATE ON public.merchants
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_wallets_updated_at BEFORE UPDATE ON public.wallets
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_transactions_updated_at BEFORE UPDATE ON public.transactions
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- 8. AUTO-CREATE PROFILE ON USER SIGNUP
-- ============================================================================
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, email, role, phone, preferred_language)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', ''),
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'role', 'standardUser'),
    COALESCE(NEW.raw_user_meta_data->>'phone', NULL),
    COALESCE(NEW.raw_user_meta_data->>'preferred_language', 'fr')
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ============================================================================
-- 9. AUTO-CREATE WALLET FOR USERS
-- ============================================================================
CREATE OR REPLACE FUNCTION public.handle_new_profile()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.role IN ('standardUser', 'merchant') THEN
    INSERT INTO public.wallets (owner_type, profile_id, currency_code)
    VALUES ('user', NEW.id, 'EUR');
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER on_profile_created
  AFTER INSERT ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_profile();

-- ============================================================================
-- 10. AUTO-CREATE WALLET FOR MERCHANTS
-- ============================================================================
CREATE OR REPLACE FUNCTION public.handle_new_merchant()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.wallets (owner_type, merchant_id, currency_code)
  VALUES ('merchant', NEW.id, 'EUR');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER on_merchant_created
  AFTER INSERT ON public.merchants
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_merchant();

-- ============================================================================
-- 11. ROW LEVEL SECURITY (RLS)
-- ============================================================================

-- Enable RLS on all tables
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.merchants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallet_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.merchant_status_history ENABLE ROW LEVEL SECURITY;

-- Profiles policies
CREATE POLICY "Users can view their own profile"
  ON public.profiles FOR SELECT
  USING (auth.uid() = id);

CREATE POLICY "Users can update their own profile"
  ON public.profiles FOR UPDATE
  USING (auth.uid() = id);

CREATE POLICY "Admins can view all profiles"
  ON public.profiles FOR SELECT
  USING ((SELECT role FROM public.profiles WHERE id = auth.uid()) = 'admin');

-- Merchants policies
CREATE POLICY "Merchants can view their own merchant profile"
  ON public.merchants FOR SELECT
  USING (auth.uid() = profile_id);

CREATE POLICY "Merchants can update their own merchant profile"
  ON public.merchants FOR UPDATE
  USING (auth.uid() = profile_id);

CREATE POLICY "Admins can view all merchants"
  ON public.merchants FOR SELECT
  USING ((SELECT role FROM public.profiles WHERE id = auth.uid()) = 'admin');

CREATE POLICY "Admins can update all merchants"
  ON public.merchants FOR UPDATE
  USING ((SELECT role FROM public.profiles WHERE id = auth.uid()) = 'admin');

-- Wallets policies
CREATE POLICY "Users can view their own wallet"
  ON public.wallets FOR SELECT
  USING (
    auth.uid() = profile_id OR
    auth.uid() IN (SELECT profile_id FROM public.merchants WHERE id = merchant_id) OR
    (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'admin'
  );

-- Transactions policies
CREATE POLICY "Users can view their own transactions"
  ON public.transactions FOR SELECT
  USING (
    auth.uid() = sender_profile_id OR
    auth.uid() = receiver_profile_id OR
    auth.uid() IN (SELECT profile_id FROM public.merchants WHERE id = receiver_merchant_id) OR
    (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'admin'
  );

-- Wallet entries policies
CREATE POLICY "Users can view their wallet entries"
  ON public.wallet_entries FOR SELECT
  USING (
    wallet_id IN (SELECT id FROM public.wallets WHERE profile_id = auth.uid() OR merchant_id IN (SELECT id FROM public.merchants WHERE profile_id = auth.uid())) OR
    (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'admin'
  );

-- ============================================================================
-- 12. ATOMIC MONEY TRANSFER FUNCTIONS (RPC)
-- ============================================================================

-- Transfer from user to user
CREATE OR REPLACE FUNCTION transfer_user_to_user(
  receiver_user_id UUID,
  transfer_amount DECIMAL,
  transfer_note TEXT DEFAULT NULL
)
RETURNS JSON AS $$
DECLARE
  sender_id UUID;
  sender_wallet_record RECORD;
  receiver_wallet_record RECORD;
  new_transaction_id UUID;
  transaction_ref TEXT;
BEGIN
  sender_id := auth.uid();
  
  -- Validate sender
  IF sender_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;
  
  -- Validate amount
  IF transfer_amount <= 0 THEN
    RETURN json_build_object('success', false, 'error', 'Invalid amount');
  END IF;
  
  -- Lock and get sender wallet
  SELECT * INTO sender_wallet_record FROM public.wallets
  WHERE profile_id = sender_id AND owner_type = 'user' AND is_active = true
  FOR UPDATE;
  
  IF sender_wallet_record IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Sender wallet not found');
  END IF;
  
  -- Check sufficient balance
  IF sender_wallet_record.balance < transfer_amount THEN
    RETURN json_build_object('success', false, 'error', 'Insufficient balance');
  END IF;
  
  -- Lock and get receiver wallet
  SELECT * INTO receiver_wallet_record FROM public.wallets
  WHERE profile_id = receiver_user_id AND owner_type = 'user' AND is_active = true
  FOR UPDATE;
  
  IF receiver_wallet_record IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Receiver wallet not found');
  END IF;
  
  -- Generate transaction reference
  transaction_ref := generate_transaction_reference();
  
  -- Create transaction
  INSERT INTO public.transactions (
    transaction_reference, sender_profile_id, sender_wallet_id,
    receiver_profile_id, receiver_wallet_id, amount, currency_code,
    note, type, status, completed_at
  ) VALUES (
    transaction_ref, sender_id, sender_wallet_record.id,
    receiver_user_id, receiver_wallet_record.id, transfer_amount, sender_wallet_record.currency_code,
    transfer_note, 'userToUser', 'completed', NOW()
  ) RETURNING id INTO new_transaction_id;
  
  -- Debit sender wallet
  UPDATE public.wallets SET balance = balance - transfer_amount
  WHERE id = sender_wallet_record.id;
  
  INSERT INTO public.wallet_entries (wallet_id, transaction_id, entry_type, amount, balance_before, balance_after)
  VALUES (sender_wallet_record.id, new_transaction_id, 'debit', transfer_amount, sender_wallet_record.balance, sender_wallet_record.balance - transfer_amount);
  
  -- Credit receiver wallet
  UPDATE public.wallets SET balance = balance + transfer_amount
  WHERE id = receiver_wallet_record.id;
  
  INSERT INTO public.wallet_entries (wallet_id, transaction_id, entry_type, amount, balance_before, balance_after)
  VALUES (receiver_wallet_record.id, new_transaction_id, 'credit', transfer_amount, receiver_wallet_record.balance, receiver_wallet_record.balance + transfer_amount);
  
  RETURN json_build_object('success', true, 'transaction_id', new_transaction_id, 'transaction_reference', transaction_ref);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Transfer from user to merchant
CREATE OR REPLACE FUNCTION transfer_user_to_merchant(
  merchant_unique_id TEXT,
  transfer_amount DECIMAL,
  transfer_note TEXT DEFAULT NULL
)
RETURNS JSON AS $$
DECLARE
  sender_id UUID;
  sender_wallet_record RECORD;
  merchant_record RECORD;
  merchant_wallet_record RECORD;
  new_transaction_id UUID;
  transaction_ref TEXT;
BEGIN
  sender_id := auth.uid();
  
  IF sender_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;
  
  IF transfer_amount <= 0 THEN
    RETURN json_build_object('success', false, 'error', 'Invalid amount');
  END IF;
  
  -- Get merchant
  SELECT * INTO merchant_record FROM public.merchants
  WHERE unique_merchant_id = merchant_unique_id AND status = 'approved';
  
  IF merchant_record IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Merchant not found or not approved');
  END IF;
  
  -- Lock sender wallet
  SELECT * INTO sender_wallet_record FROM public.wallets
  WHERE profile_id = sender_id AND owner_type = 'user' AND is_active = true
  FOR UPDATE;
  
  IF sender_wallet_record IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Sender wallet not found');
  END IF;
  
  IF sender_wallet_record.balance < transfer_amount THEN
    RETURN json_build_object('success', false, 'error', 'Insufficient balance');
  END IF;
  
  -- Lock merchant wallet
  SELECT * INTO merchant_wallet_record FROM public.wallets
  WHERE merchant_id = merchant_record.id AND owner_type = 'merchant' AND is_active = true
  FOR UPDATE;
  
  IF merchant_wallet_record IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Merchant wallet not found');
  END IF;
  
  transaction_ref := generate_transaction_reference();
  
  INSERT INTO public.transactions (
    transaction_reference, sender_profile_id, sender_wallet_id,
    receiver_merchant_id, receiver_wallet_id, amount, currency_code,
    note, type, status, completed_at
  ) VALUES (
    transaction_ref, sender_id, sender_wallet_record.id,
    merchant_record.id, merchant_wallet_record.id, transfer_amount, sender_wallet_record.currency_code,
    transfer_note, 'userToMerchant', 'completed', NOW()
  ) RETURNING id INTO new_transaction_id;
  
  UPDATE public.wallets SET balance = balance - transfer_amount
  WHERE id = sender_wallet_record.id;
  
  INSERT INTO public.wallet_entries (wallet_id, transaction_id, entry_type, amount, balance_before, balance_after)
  VALUES (sender_wallet_record.id, new_transaction_id, 'debit', transfer_amount, sender_wallet_record.balance, sender_wallet_record.balance - transfer_amount);
  
  UPDATE public.wallets SET balance = balance + transfer_amount
  WHERE id = merchant_wallet_record.id;
  
  INSERT INTO public.wallet_entries (wallet_id, transaction_id, entry_type, amount, balance_before, balance_after)
  VALUES (merchant_wallet_record.id, new_transaction_id, 'credit', transfer_amount, merchant_wallet_record.balance, merchant_wallet_record.balance + transfer_amount);
  
  RETURN json_build_object('success', true, 'transaction_id', new_transaction_id, 'transaction_reference', transaction_ref);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- END OF SCHEMA
-- ============================================================================
