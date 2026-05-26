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
  theme: 'dark' | 'light';
  language: 'en' | 'es' | 'fr' | 'de';
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
  setTheme: (theme: 'dark' | 'light') => void;
  setLanguage: (lang: 'en' | 'es' | 'fr' | 'de') => void;
  toggleNotifications: () => void;
  setLoading: (loading: boolean) => void;
  resetAll: () => void;
}

export const useAppStore = create<AppState>((set) => ({
  user: null,
  wallets: [
    { id: 'w1', currency: 'USD', balance: 14850.50, accountNumber: 'US98 7654 3210 1192', routingNumber: '021000021' },
    { id: 'w2', currency: 'EUR', balance: 5240.20, accountNumber: 'DE89 3704 0044 0532 0130 00', iban: 'DE89370400440532013000', bic: 'DBREDEDDXXX' },
    { id: 'w3', currency: 'GBP', balance: 890.75, accountNumber: 'GB33 BUBA 4004 0122 9382 11', iban: 'GB33BUBA40040122938211', bic: 'BUBADB2L' },
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
    { id: 't1', type: 'send', amount: 150.00, currency: 'USD', title: 'Transfer to John Doe', subtitle: 'Global Transfer', date: '2026-05-25T14:32:00.000Z', status: 'completed' },
    { id: 't2', type: 'receive', amount: 2450.00, currency: 'USD', title: 'Salary Deposit', subtitle: 'Grey Technology Inc.', date: '2026-05-24T08:15:00.000Z', status: 'completed' },
    { id: 't3', type: 'exchange', amount: 400.00, currency: 'EUR', title: 'Exchanged USD to EUR', subtitle: 'Rate: 1 USD = 0.92 EUR', date: '2026-05-22T19:04:00.000Z', status: 'completed' },
    { id: 't4', type: 'card_payment', amount: 45.99, currency: 'USD', title: 'Netflix Premium', subtitle: 'Visa *1024', date: '2026-05-21T11:45:00.000Z', status: 'completed' },
    { id: 't5', type: 'card_payment', amount: 89.00, currency: 'USD', title: 'Amazon AWS Cloud', subtitle: 'Visa *1024', date: '2026-05-20T04:22:00.000Z', status: 'completed' },
    { id: 't6', type: 'receive', amount: 75.00, currency: 'GBP', title: 'Refund payment', subtitle: 'ASOS Marketplace', date: '2026-05-18T16:10:00.000Z', status: 'completed' },
  ],
  kyc: {
    idUploaded: false,
    selfieUploaded: false,
    status: 'none'
  },
  theme: 'dark',
  language: 'en',
  notificationsEnabled: true,
  isLoading: false,

  setUser: (user) => set({ user }),
  setWallets: (wallets) => set({ wallets }),
  updateWalletBalance: (currency, amount) => set((state) => ({
    wallets: state.wallets.map((w) => 
      w.currency === currency ? { ...w, balance: w.balance + amount } : w
    )
  })),
  setCards: (cards) => set({ cards }),
  addCard: (card) => set((state) => {
    // Generate static details
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
    return { cards: [newCard, ...state.cards] };
  }),
  toggleFreezeCard: (cardId) => set((state) => ({
    cards: state.cards.map((c) => c.id === cardId ? { ...c, isFrozen: !c.isFrozen } : c)
  })),
  toggleCardDetails: (cardId) => set((state) => ({
    cards: state.cards.map((c) => c.id === cardId ? { ...c, showDetails: !c.showDetails } : c)
  })),
  updateCardLimit: (cardId, limit) => set((state) => ({
    cards: state.cards.map((c) => c.id === cardId ? { ...c, spendingLimit: limit } : c)
  })),
  addTransaction: (tx) => set((state) => {
    const newTx: Transaction = {
      ...tx,
      id: `t_${Date.now()}`,
      date: new Date().toISOString(),
    };
    return { transactions: [newTx, ...state.transactions] };
  }),
  updateKYC: (kycUpdate) => set((state) => ({
    kyc: { ...state.kyc, ...kycUpdate }
  })),
  setTheme: (theme) => set({ theme }),
  setLanguage: (language) => set({ language }),
  toggleNotifications: () => set((state) => ({ notificationsEnabled: !state.notificationsEnabled })),
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
      { id: 't1', type: 'send', amount: 150.00, currency: 'USD', title: 'Transfer to John Doe', subtitle: 'Global Transfer', date: '2026-05-25T14:32:00.000Z', status: 'completed' },
      { id: 't2', type: 'receive', amount: 2450.00, currency: 'USD', title: 'Salary Deposit', subtitle: 'Grey Technology Inc.', date: '2026-05-24T08:15:00.000Z', status: 'completed' },
    ]
  })
}));
