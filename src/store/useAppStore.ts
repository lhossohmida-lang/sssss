import { create } from 'zustand';

export interface Wallet {
  id: string;
  currency: 'USD' | 'EUR' | 'GBP';
  balance: number;
  accountNumber: string;
  routingNumber?: string;
  iban?: string;
  bic?: string;
}

export interface Card {
  id: string;
  number: string;
  holder: string;
  expiry: string;
  cvv: string;
  brand: 'Visa' | 'Mastercard';
  type: 'Virtual' | 'Physical';
  isFrozen: boolean;
  spendingLimit: number;
  showDetails: boolean;
  color: string;
  design: 'premium' | 'gold' | 'neon' | 'glass';
}

export interface Transaction {
  id: string;
  type: 'send' | 'receive' | 'exchange' | 'card_payment';
  amount: number;
  currency: 'USD' | 'EUR' | 'GBP';
  title: string;
  subtitle: string;
  date: string;
  status: 'completed' | 'pending' | 'failed';
  recipientId?: string;
  senderId?: string;
}

export interface KYCStatus {
  idUploaded: boolean;
  selfieUploaded: boolean;
  status: 'none' | 'pending' | 'verified' | 'rejected';
  submittedAt?: string;
}

export interface AuditLog {
  id: string;
  timestamp: string;
  action: string;
  category: 'auth' | 'transaction' | 'card' | 'kyc' | 'system';
  description: string;
}

interface AppState {
  user: {
    uid: string;
    email: string;
    fullName: string;
    phoneNumber?: string;
    photoURL?: string;
    isPremium: boolean;
  } | null;
  wallets: Wallet[];
  cards: Card[];
  transactions: Transaction[];
  kyc: KYCStatus;
  logs: AuditLog[];
  theme: 'dark' | 'light';
  language: 'en' | 'es' | 'fr' | 'de' | 'ar';
  notificationsEnabled: boolean;
  isLoading: boolean;
  
  // Actions
  setUser: (user: AppState['user']) => void;
  setWallets: (wallets: Wallet[]) => void;
  updateWalletBalance: (currency: 'USD' | 'EUR' | 'GBP', amount: number) => void;
  setCards: (cards: Card[]) => void;
  addCard: (card: Omit<Card, 'id' | 'number' | 'expiry' | 'cvv'>) => void;
  toggleFreezeCard: (cardId: string) => void;
  toggleCardDetails: (cardId: string) => void;
  updateCardLimit: (cardId: string, limit: number) => void;
  addTransaction: (tx: Omit<Transaction, 'id' | 'date'>) => void;
  updateKYC: (kycUpdate: Partial<KYCStatus>) => void;
  addLog: (action: string, category: AuditLog['category'], description: string) => void;
  setTheme: (theme: 'dark' | 'light') => void;
  setLanguage: (lang: 'en' | 'es' | 'fr' | 'de' | 'ar') => void;
  toggleNotifications: () => void;
  setLoading: (loading: boolean) => void;
  resetAll: () => void;
}

export const useAppStore = create<AppState>((set) => ({
  user: null,
  wallets: [
    { id: 'w1', currency: 'USD', balance: 20.00, accountNumber: 'US98 7654 3210 1192', routingNumber: '021000021' },
    { id: 'w2', currency: 'EUR', balance: 0.00, accountNumber: 'DE89 3704 0044 0532 0130 00', iban: 'DE89370400440532013000', bic: 'DBREDEDDXXX' },
    { id: 'w3', currency: 'GBP', balance: 0.00, accountNumber: 'GB33 BUBA 4004 0122 9382 11', iban: 'GB33BUBA40040122938211', bic: 'BUBADB2L' },
  ],
  cards: [
    {
      id: 'c1',
      number: '4112 8847 2938 1024',
      holder: 'ALEXANDER MOREAU',
      expiry: '09/29',
      cvv: '394',
      brand: 'Visa',
      type: 'Virtual',
      isFrozen: false,
      spendingLimit: 2500,
      showDetails: false,
      color: '#00FF66',
      design: 'premium',
    },
    {
      id: 'c2',
      number: '5399 2201 9984 7421',
      holder: 'ALEXANDER MOREAU',
      expiry: '12/28',
      cvv: '821',
      brand: 'Visa',
      type: 'Virtual',
      isFrozen: true,
      spendingLimit: 10000,
      showDetails: false,
      color: '#A855F7',
      design: 'neon',
    }
  ],
  transactions: [
    { id: 't1', type: 'card_payment', amount: 5.00, currency: 'USD', title: 'سحب فايسبوك', subtitle: '25 ماي', date: '2026-05-25T12:00:00.000Z', status: 'completed' },
    { id: 't2', type: 'receive', amount: 30.00, currency: 'USD', title: 'ادخال رصيد', subtitle: 'إيداع نقدي', date: '2026-05-24T18:00:00.000Z', status: 'completed' },
    { id: 't3', type: 'card_payment', amount: 4.00, currency: 'USD', title: 'سحب فايسبوك', subtitle: '24 ماي', date: '2026-05-24T12:00:00.000Z', status: 'completed' },
    { id: 't4', type: 'card_payment', amount: 5.00, currency: 'USD', title: 'سحب فايسبوك', subtitle: '23 ماي', date: '2026-05-23T12:00:00.000Z', status: 'completed' },
  ],
  kyc: {
    idUploaded: false,
    selfieUploaded: false,
    status: 'none'
  },
  logs: [
    { id: 'log_01', timestamp: new Date(Date.now() - 3600000 * 2).toISOString(), action: 'SYSTEM_BOOT', category: 'system', description: 'AES-256 cryptographic local storage cache initialized.' },
    { id: 'log_02', timestamp: new Date(Date.now() - 3600000).toISOString(), action: 'FIREBASE_CONNECT', category: 'system', description: 'Established Firestore dynamic pipeline connection at grye-52952.' },
    { id: 'log_03', timestamp: new Date().toISOString(), action: 'APP_READY', category: 'system', description: 'JWT authentication tunnel secured. Dark luxury UI layer rendered.' }
  ],
  theme: 'dark',
  language: 'ar',
  notificationsEnabled: true,
  isLoading: false,

  setUser: (user) => set((state) => {
    const updatedState: Partial<AppState> = { user };
    if (user) {
      const newLog: AuditLog = {
        id: `log_${Date.now()}`,
        timestamp: new Date().toISOString(),
        action: 'AUTH_SUCCESS',
        category: 'auth',
        description: `Session opened and JWT authenticated for ${user.fullName} (${user.email}).`
      };
      updatedState.logs = [newLog, ...state.logs];
    }
    return updatedState;
  }),
  
  setWallets: (wallets) => set({ wallets }),
  
  updateWalletBalance: (currency, amount) => set((state) => {
    const newLog: AuditLog = {
      id: `log_${Date.now()}`,
      timestamp: new Date().toISOString(),
      action: 'BALANCE_MUTATED',
      category: 'transaction',
      description: `Wallet ledger balance for ${currency} adjusted by ${amount > 0 ? '+' : ''}${amount.toFixed(2)}.`
    };
    return {
      wallets: state.wallets.map((w) => 
        w.currency === currency ? { ...w, balance: w.balance + amount } : w
      ),
      logs: [newLog, ...state.logs]
    };
  }),

  setCards: (cards) => set({ cards }),
  
  addCard: (card) => set((state) => {
    const randomCardNo = '4112 ' + Array.from({length: 3}, () => Math.floor(1000 + Math.random() * 9000).toString()).join(' ');
    const randomCvv = Math.floor(100 + Math.random() * 900).toString();
    const expiryDate = `06/31`;
    const newCard: Card = {
      ...card,
      id: `c_${Date.now()}`,
      number: randomCardNo,
      expiry: expiryDate,
      cvv: randomCvv,
      isFrozen: false,
      showDetails: false
    };
    const newLog: AuditLog = {
      id: `log_${Date.now()}`,
      timestamp: new Date().toISOString(),
      action: 'CARD_CREATED',
      category: 'card',
      description: `New virtual ${card.brand} card (ending *${randomCardNo.slice(-4)}) successfully generated.`
    };
    return { 
      cards: [newCard, ...state.cards],
      logs: [newLog, ...state.logs]
    };
  }),

  toggleFreezeCard: (cardId) => set((state) => {
    const targetCard = state.cards.find((c) => c.id === cardId);
    const newLog: AuditLog = {
      id: `log_${Date.now()}`,
      timestamp: new Date().toISOString(),
      action: 'CARD_FREEZE_TOGGLE',
      category: 'card',
      description: `Virtual card ending *${targetCard?.number.slice(-4) || 'N/A'} is now ${targetCard?.isFrozen ? 'unfrozen' : 'frozen'}.`
    };
    return {
      cards: state.cards.map((c) => c.id === cardId ? { ...c, isFrozen: !c.isFrozen } : c),
      logs: [newLog, ...state.logs]
    };
  }),

  toggleCardDetails: (cardId) => set((state) => {
    const targetCard = state.cards.find((c) => c.id === cardId);
    const newLog: AuditLog = {
      id: `log_${Date.now()}`,
      timestamp: new Date().toISOString(),
      action: 'CARD_DETAILS_SHOWN',
      category: 'card',
      description: `Sensitive security credentials revealed for card ending *${targetCard?.number.slice(-4) || 'N/A'}.`
    };
    return {
      cards: state.cards.map((c) => c.id === cardId ? { ...c, showDetails: !c.showDetails } : c),
      logs: [newLog, ...state.logs]
    };
  }),

  updateCardLimit: (cardId, limit) => set((state) => {
    const targetCard = state.cards.find((c) => c.id === cardId);
    const newLog: AuditLog = {
      id: `log_${Date.now()}`,
      timestamp: new Date().toISOString(),
      action: 'CARD_LIMIT_ALTERED',
      category: 'card',
      description: `Spend limit threshold for card ending *${targetCard?.number.slice(-4) || 'N/A'} altered to $${limit.toLocaleString()}.`
    };
    return {
      cards: state.cards.map((c) => c.id === cardId ? { ...c, spendingLimit: limit } : c),
      logs: [newLog, ...state.logs]
    };
  }),

  addTransaction: (tx) => set((state) => {
    const newTx: Transaction = {
      ...tx,
      id: `t_${Date.now()}`,
      date: new Date().toISOString(),
    };
    const newLog: AuditLog = {
      id: `log_${Date.now()}`,
      timestamp: new Date().toISOString(),
      action: 'TRANSACTION_LOGGED',
      category: 'transaction',
      description: `Cryptographic ledger entry recorded: ${tx.title} (${tx.currency} ${tx.amount.toFixed(2)}).`
    };
    return { 
      transactions: [newTx, ...state.transactions],
      logs: [newLog, ...state.logs]
    };
  }),

  updateKYC: (kycUpdate) => set((state) => {
    const newLog: AuditLog = {
      id: `log_${Date.now()}`,
      timestamp: new Date().toISOString(),
      action: 'KYC_MUTATED',
      category: 'kyc',
      description: `Identity verification status updated to ${kycUpdate.status || state.kyc.status}.`
    };
    return {
      kyc: { ...state.kyc, ...kycUpdate },
      logs: [newLog, ...state.logs]
    };
  }),

  addLog: (action, category, description) => set((state) => {
    const newLog: AuditLog = {
      id: `log_${Date.now()}`,
      timestamp: new Date().toISOString(),
      action,
      category,
      description
    };
    return { logs: [newLog, ...state.logs] };
  }),

  setTheme: (theme) => set({ theme }),
  
  setLanguage: (language) => set((state) => {
    const newLog: AuditLog = {
      id: `log_${Date.now()}`,
      timestamp: new Date().toISOString(),
      action: 'LANG_MUTATED',
      category: 'system',
      description: `System localization dictionary updated to ${language.toUpperCase()}.`
    };
    return { language, logs: [newLog, ...state.logs] };
  }),
  
  toggleNotifications: () => set((state) => {
    const newLog: AuditLog = {
      id: `log_${Date.now()}`,
      timestamp: new Date().toISOString(),
      action: 'FCM_NOTIF_TOGGLE',
      category: 'system',
      description: `Push notification status toggled to ${!state.notificationsEnabled ? 'ENABLED' : 'DISABLED'}.`
    };
    return { 
      notificationsEnabled: !state.notificationsEnabled,
      logs: [newLog, ...state.logs]
    };
  }),

  setLoading: (isLoading) => set({ isLoading }),
  
  resetAll: () => set({
    user: null,
    kyc: { idUploaded: false, selfieUploaded: false, status: 'none' },
    cards: [
      {
        id: 'c1',
        number: '4112 8847 2938 1024',
        holder: 'ALEXANDER MOREAU',
        expiry: '09/29',
        cvv: '394',
        brand: 'Visa',
        type: 'Virtual',
        isFrozen: false,
        spendingLimit: 2500,
        showDetails: false,
        color: '#00FF66',
        design: 'premium',
      }
    ],
    transactions: [
      { id: 't1', type: 'card_payment', amount: 5.00, currency: 'USD', title: 'سحب فايسبوك', subtitle: '25 ماي', date: '2026-05-25T12:00:00.000Z', status: 'completed' },
      { id: 't2', type: 'receive', amount: 30.00, currency: 'USD', title: 'ادخال رصيد', subtitle: 'إيداع نقدي', date: '2026-05-24T18:00:00.000Z', status: 'completed' },
      { id: 't3', type: 'card_payment', amount: 4.00, currency: 'USD', title: 'سحب فايسبوك', subtitle: '24 ماي', date: '2026-05-24T12:00:00.000Z', status: 'completed' },
      { id: 't4', type: 'card_payment', amount: 5.00, currency: 'USD', title: 'سحب فايسبوك', subtitle: '23 ماي', date: '2026-05-23T12:00:00.000Z', status: 'completed' },
    ],
    logs: [
      { id: 'log_rst', timestamp: new Date().toISOString(), action: 'CACHE_RESET', category: 'system', description: 'Secure storage cache successfully cleared. Token logs purged.' }
    ]
  })
}));
