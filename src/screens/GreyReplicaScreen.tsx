import React, { useState } from 'react';
import {
  Dimensions,
  Platform,
  SafeAreaView,
  ScrollView,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import {
  ArrowLeft,
  ArrowUpRight,
  Banknote,
  ChevronDown,
  ChevronRight,
  CircleDollarSign,
  Copy,
  CreditCard,
  FileText,
  Gift,
  Home,
  Info,
  LockKeyhole,
  Menu,
  MessageCircle,
  Plus,
  ReceiptText,
  RefreshCw,
  Snowflake,
  Smartphone,
  Trash2,
  Users,
  WalletCards,
  Wifi,
  X,
} from 'lucide-react';

type PageKey = 'home' | 'accounts' | 'payments' | 'transactions' | 'cards' | 'reports';

const { width } = Dimensions.get('window');
const isWeb = Platform.OS === 'web';

const NAV_ITEMS = [
  { key: 'home' as PageKey, label: 'Home', Icon: Home },
  { key: 'accounts' as PageKey, label: 'Accounts', Icon: WalletCards },
  { key: 'payments' as PageKey, label: 'Payments', Icon: Banknote },
  { key: 'transactions' as PageKey, label: 'Transactions', Icon: ReceiptText },
  { key: 'cards' as PageKey, label: 'Cards', Icon: CreditCard },
  { key: 'reports' as PageKey, label: 'Reports & Statements', Icon: FileText },
];

const BALANCES = [
  { name: 'US Dollars', symbol: '$', amount: '$5.95', badge: 'US', color: '#f1f5ff' },
  { name: 'Tether', symbol: 'T', amount: '\u20AE0.01', badge: 'T', color: '#e8fff5' },
  { name: 'USD Coin', symbol: '$', amount: '$0.00', badge: '$', color: '#edf4ff' },
];

const QUICK_ACTIONS = [
  {
    title: 'Pay Bills',
    copy: 'Pay for your internet, cable subscription and other utility bills all in one place',
    Icon: ReceiptText,
    tint: '#fff9ed',
  },
  {
    title: 'Virtual card',
    copy: 'Shop, subscribe and pay bills securely online',
    Icon: CreditCard,
    tint: '#f7f6ff',
  },
  {
    title: 'Invoices',
    copy: 'Create and send invoices to clients',
    Icon: FileText,
    tint: '#eef7ff',
  },
];

const PAYMENT_ACTIONS = [
  {
    title: 'Buy Data',
    copy: 'Enjoy uninterrupted internet access with easy and convenient mobile data top-ups',
    Icon: Smartphone,
    tint: '#f7f4ff',
  },
  {
    title: 'Pay Bills',
    copy: 'Pay for your internet, cable subscription and other utility bills all in one place',
    Icon: ReceiptText,
    tint: '#fffaf0',
  },
  {
    title: 'Gift Cards',
    copy: 'Buy gift cards for yourself or your loved ones',
    Icon: Gift,
    tint: '#f6fff1',
  },
];

const SEND_ACTIONS = [
  {
    title: 'Send Money',
    copy: 'Transfer funds to Grey users and external accounts',
    Icon: ArrowUpRight,
    tint: '#f0fffb',
  },
  {
    title: 'Bank transfer',
    copy: 'Send money to supported foreign bank accounts',
    Icon: Banknote,
    tint: '#f6f8ff',
  },
];

const TRANSACTIONS = [
  { date: '25 May 2026, 17:32:47', amount: '- $5.00', type: 'Withdraw', description: 'FACEBK *XKWH3N5M92', status: 'Processing' },
  { date: '24 May 2026, 14:58:19', amount: '- $10.00', type: 'Withdraw', description: 'FACEBK *XKWH3N5M92', status: 'Completed' },
  { date: '23 May 2026, 14:57:35', amount: '- $15.00', type: 'Withdraw', description: 'FACEBK *XKWH3N5M92', status: 'Completed' },
  { date: '23 May 2026, 14:54:21', amount: '- $6.01', type: 'Swap', description: 'USD to USDT', status: 'Completed' },
  { date: '22 May 2026, 18:02:44', amount: '- USDT15.00', type: 'Swap', description: 'USDT to USD', status: 'Completed' },
];

export const GreyReplicaScreen: React.FC = () => {
  const [activePage, setActivePage] = useState<PageKey>('home');
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [cardFrozen, setCardFrozen] = useState(false);
  const [toast, setToast] = useState('');

  const isWide = width >= 720;

  const openPage = (page: PageKey) => {
    setActivePage(page);
    setDrawerOpen(false);
  };

  const showToast = (message: string) => {
    setToast(message);
    setTimeout(() => setToast(''), 2200);
  };

  const title =
    activePage === 'home'
      ? 'Hello abdelahe,'
      : activePage === 'accounts'
        ? 'Accounts'
        : activePage === 'payments'
          ? 'Payments'
          : activePage === 'transactions'
            ? 'Transactions'
            : activePage === 'cards'
              ? 'Cards'
              : 'Reports & Statements';

  return (
    <SafeAreaView style={styles.safeArea}>
      <View style={styles.shell}>
        <View style={[styles.appFrame, isWide && styles.appFrameWide]}>
          <TopBar
            title={title}
            activePage={activePage}
            onMenu={() => setDrawerOpen(true)}
            onBack={activePage === 'cards' ? () => openPage('home') : undefined}
          />

          {activePage === 'home' && <DashboardPage onOpenPage={openPage} />}
          {activePage === 'accounts' && <AccountsPage />}
          {activePage === 'payments' && <PaymentsPage />}
          {activePage === 'transactions' && <TransactionsPage />}
          {activePage === 'cards' && (
            <CardsPage
              frozen={cardFrozen}
              onToggleFreeze={() => {
                setCardFrozen((value) => !value);
                showToast(cardFrozen ? 'Card has been activated' : 'Card has been deactivated');
              }}
            />
          )}
          {activePage === 'reports' && <ReportsPage />}

          <TouchableOpacity activeOpacity={0.85} style={styles.chatButton}>
            <MessageCircle size={22} color="#ffffff" />
          </TouchableOpacity>

          {toast ? (
            <View style={styles.toast}>
              <View style={styles.toastDot} />
              <Text style={styles.toastText}>{toast}</Text>
              <X size={16} color="#22663d" />
            </View>
          ) : null}

          {drawerOpen && (
            <View style={styles.drawerLayer}>
              <TouchableOpacity activeOpacity={1} style={styles.drawerScrim} onPress={() => setDrawerOpen(false)} />
              <View style={styles.drawer}>
                <View style={styles.drawerLogoRow}>
                  <GreyLogo size="large" />
                  <TouchableOpacity onPress={() => setDrawerOpen(false)} style={styles.drawerClose}>
                    <X size={19} color="#111827" />
                  </TouchableOpacity>
                </View>

                <View style={styles.navList}>
                  {NAV_ITEMS.map(({ key, label, Icon }) => {
                    const active = key === activePage;
                    return (
                      <TouchableOpacity
                        key={key}
                        activeOpacity={0.85}
                        onPress={() => openPage(key)}
                        style={[styles.navItem, active && styles.navItemActive]}
                      >
                        <Icon size={17} color={active ? '#2f6fe4' : '#9aa3b2'} />
                        <Text style={[styles.navText, active && styles.navTextActive]}>{label}</Text>
                      </TouchableOpacity>
                    );
                  })}
                </View>

                <View style={styles.drawerBottom}>
                  <TouchableOpacity activeOpacity={0.85} style={styles.communityRow}>
                    <Users size={17} color="#9aa3b2" />
                    <Text style={styles.communityText}>Community</Text>
                  </TouchableOpacity>

                  <View style={styles.referralCard}>
                    <Text style={styles.referralTitle}>Spread the word and earn</Text>
                    <Text style={styles.referralAmount}>$5</Text>
                    <View style={styles.referralStripe} />
                  </View>
                </View>
              </View>
            </View>
          )}
        </View>
      </View>
    </SafeAreaView>
  );
};

const TopBar: React.FC<{
  title: string;
  activePage: PageKey;
  onMenu: () => void;
  onBack?: () => void;
}> = ({ title, activePage, onMenu, onBack }) => (
  <View style={styles.topBar}>
    <View style={styles.topTitleRow}>
      {onBack && (
        <TouchableOpacity onPress={onBack} style={styles.backButton}>
          <ArrowLeft size={18} color="#111827" />
        </TouchableOpacity>
      )}
      {activePage === 'transactions' ? <GreyLogo size="large" /> : null}
      {activePage !== 'transactions' && (
        <Text style={styles.topTitle}>
          {title}
          {activePage === 'home' ? <Text style={styles.handWave}> {'\uD83D\uDC4B'}</Text> : null}
        </Text>
      )}
    </View>

    <View style={styles.topTools}>
      <TouchableOpacity activeOpacity={0.85} style={styles.languagePill}>
        <Text style={styles.languageText}>Arabic</Text>
        <ChevronDown size={15} color="#111827" />
      </TouchableOpacity>
      <View style={styles.avatar}>
        <Text style={styles.avatarText}>AB</Text>
      </View>
      <TouchableOpacity activeOpacity={0.85} style={styles.menuButton} onPress={onMenu}>
        <Menu size={25} color="#111827" />
      </TouchableOpacity>
    </View>
  </View>
);

const DashboardPage: React.FC<{ onOpenPage: (page: PageKey) => void }> = ({ onOpenPage }) => (
  <ScrollView style={styles.page} contentContainerStyle={styles.pageContent} showsVerticalScrollIndicator={false}>
    <View style={styles.balancePanel}>
      <View style={styles.balanceTop}>
        <View>
          <View style={styles.balanceLabelRow}>
            <Text style={styles.balanceLabel}>Total balance</Text>
            <CurrencyStack />
            <ChevronDown size={13} color="#6d7786" />
          </View>
          <View style={styles.amountRow}>
            <Text style={styles.totalAmount}>$5.96</Text>
            <View style={styles.syncMini}>
              <RefreshCw size={14} color="#2f6fe4" />
            </View>
          </View>
        </View>

        <View style={styles.mainActions}>
          <ActionCircle label="Add money" Icon={Plus} onPress={() => onOpenPage('accounts')} />
          <ActionCircle label="Send" Icon={ArrowUpRight} onPress={() => onOpenPage('payments')} />
          <ActionCircle label="Convert" Icon={RefreshCw} onPress={() => onOpenPage('transactions')} />
        </View>
      </View>

      <View style={styles.panelDivider} />

      <Text style={styles.sectionHeading}>My Balances</Text>
      <ScrollView horizontal showsHorizontalScrollIndicator={false}>
        <View style={styles.balanceCardsRow}>
          {BALANCES.map((item) => (
            <TouchableOpacity key={item.name} activeOpacity={0.85} style={styles.currencyCard}>
              <View style={[styles.currencyBadge, { backgroundColor: item.color }]}>
                <Text style={styles.currencyBadgeText}>{item.badge}</Text>
              </View>
              <Text style={styles.currencyName}>{item.name}</Text>
              <Text style={styles.currencyAmount}>{item.amount}</Text>
              <View style={styles.currencyChevron}>
                <ChevronRight size={17} color="#5f6673" />
              </View>
            </TouchableOpacity>
          ))}
        </View>
      </ScrollView>
    </View>

    <SetupCard />

    <View style={styles.sectionBlock}>
      <Text style={styles.sectionHeading}>Quick Actions</Text>
      <ScrollView horizontal showsHorizontalScrollIndicator={false}>
        <View style={styles.quickRow}>
          {QUICK_ACTIONS.map((item) => (
            <ActionTile key={item.title} {...item} onPress={() => onOpenPage(item.title === 'Virtual card' ? 'cards' : 'payments')} />
          ))}
        </View>
      </ScrollView>
    </View>
  </ScrollView>
);

const AccountsPage: React.FC = () => (
  <ScrollView style={styles.page} contentContainerStyle={styles.pageContent} showsVerticalScrollIndicator={false}>
    <View style={styles.sectionBlock}>
      <Text style={styles.sectionHeading}>My Balances</Text>
      {BALANCES.map((item) => (
        <View key={item.name} style={styles.accountRow}>
          <View style={[styles.currencyBadge, { backgroundColor: item.color }]}>
            <Text style={styles.currencyBadgeText}>{item.badge}</Text>
          </View>
          <View style={styles.accountMeta}>
            <Text style={styles.accountName}>{item.name}</Text>
            <Text style={styles.accountSub}>Available balance</Text>
          </View>
          <Text style={styles.accountAmount}>{item.amount}</Text>
          <ChevronRight size={18} color="#798392" />
        </View>
      ))}
    </View>
  </ScrollView>
);

const PaymentsPage: React.FC = () => (
  <ScrollView style={styles.page} contentContainerStyle={styles.pageContent} showsVerticalScrollIndicator={false}>
    <View style={styles.paymentsPanel}>
      {PAYMENT_ACTIONS.map((item) => (
        <ActionTile key={item.title} {...item} wide />
      ))}
    </View>

    <View style={styles.sectionBlock}>
      <Text style={styles.sectionHeading}>Send & Receive</Text>
      {SEND_ACTIONS.map((item) => (
        <ActionTile key={item.title} {...item} wide />
      ))}
    </View>
  </ScrollView>
);

const TransactionsPage: React.FC = () => (
  <ScrollView style={styles.page} contentContainerStyle={styles.transactionsContent} showsVerticalScrollIndicator={false}>
    <View style={styles.recentTransactionsHeader}>
      <Text style={styles.recentTransactionsTitle}>Recent transactions</Text>
      <TouchableOpacity activeOpacity={0.85}>
        <Text style={styles.seeAllText}>See all</Text>
      </TouchableOpacity>
    </View>

    <View style={styles.tableCard}>
      <View style={[styles.tableRow, styles.tableHeader]}>
        <Text style={[styles.tableHeadText, styles.tableDate]}>DATE</Text>
        <Text style={[styles.tableHeadText, styles.tableAmount]}>AMOUNT</Text>
        <Text style={[styles.tableHeadText, styles.tableType]}>TYPE</Text>
        <Text style={[styles.tableHeadText, styles.tableDescription]}>DESCRIPTION</Text>
        <Text style={[styles.tableHeadText, styles.tableStatus]}>STATUS</Text>
        <View style={styles.tableChevronCol} />
      </View>
      {TRANSACTIONS.map((transaction, index) => {
        const processing = transaction.status === 'Processing';

        return (
          <View key={`${transaction.date}-${index}`} style={[styles.tableRow, index === 1 && styles.tableRowMuted]}>
            <Text style={[styles.tableCell, styles.tableDate]}>{transaction.date}</Text>
            <Text style={[styles.tableCellStrong, styles.tableAmount]}>{transaction.amount}</Text>
            <Text style={[styles.tableCell, styles.tableType]}>{transaction.type}</Text>
            <Text style={[styles.tableCell, styles.tableDescription]}>{transaction.description}</Text>
            <View style={styles.tableStatus}>
              <View style={styles.statusPill}>
                <View style={[styles.statusDot, processing ? styles.statusDotProcessing : styles.statusDotCompleted]} />
                <Text style={[styles.statusText, processing ? styles.statusTextProcessing : styles.statusTextCompleted]}>
                  {transaction.status}
                </Text>
              </View>
            </View>
            <View style={styles.tableChevronCol}>
              <ChevronRight size={22} color="#111827" />
            </View>
          </View>
        );
      })}
    </View>
  </ScrollView>
);

const CardsPage: React.FC<{ frozen: boolean; onToggleFreeze: () => void }> = ({ frozen, onToggleFreeze }) => {
  const [detailsVisible, setDetailsVisible] = useState(false);
  const [pinVisible, setPinVisible] = useState(false);

  return (
    <View style={styles.cardPageHost}>
      <ScrollView style={styles.page} contentContainerStyle={styles.pageContent} showsVerticalScrollIndicator={false}>
        <Text style={styles.cardLabel}>Add a card label <Text style={styles.editPencil}>o</Text></Text>

        <View style={[styles.visaCard, frozen && styles.visaCardFrozen]}>
          <View style={styles.cardWaveOne} />
          <View style={styles.cardWaveTwo} />
          <View style={styles.cardWaveThree} />
          <View style={styles.cardTopRow}>
            <GreyLogo light />
            <View style={styles.visaTextWrap}>
              <Text style={styles.visaText}>VISA</Text>
              <Text style={styles.visaSub}>Platinum</Text>
            </View>
          </View>
          <Text style={styles.cardNumber}>.... 2461</Text>
        </View>

        <View style={styles.cardActionRow}>
          <CardRoundAction label="Details" Icon={Info} active={detailsVisible} onPress={() => setDetailsVisible(true)} />
          <CardRoundAction label={frozen ? 'Unfreeze' : 'Freeze'} Icon={Snowflake} onPress={onToggleFreeze} outlined={frozen} />
          <CardRoundAction label="Show PIN" Icon={LockKeyhole} active={pinVisible} onPress={() => setPinVisible((value) => !value)} />
        </View>

        <View style={styles.walletStrip}>
          <View style={styles.walletIconStack}>
            <View style={[styles.walletMini, { backgroundColor: '#ffcc4d' }]} />
            <View style={[styles.walletMini, { backgroundColor: '#4eb5ff', left: 8 }]} />
            <View style={[styles.walletMini, { backgroundColor: '#34c759', left: 16 }]} />
          </View>
          <View style={styles.walletCopy}>
            <Text style={styles.walletTitle}>Add to your digital wallets</Text>
            <Text style={styles.walletDesc}>Start spending using Google Pay or Apple pay</Text>
          </View>
        </View>

        <Text style={styles.manageHeading}>MANAGE CARD</Text>
        <View style={styles.manageList}>
          <ManageRow Icon={CircleDollarSign} label="Payment limits" />
          <ManageRow Icon={CreditCard} label="Card statement" />
          <ManageRow Icon={Info} label="Card benefits" />
          <ManageRow Icon={MessageCircle} label="Where can I use my card?" />
          <ManageRow Icon={MessageCircle} label="Need help?" />
          <ManageRow Icon={Trash2} label="Delete this card" danger />
        </View>
      </ScrollView>

      {detailsVisible && (
        <View style={styles.cardDetailsOverlay}>
          <TouchableOpacity activeOpacity={1} style={styles.cardDetailsScrim} onPress={() => setDetailsVisible(false)} />
          <View style={styles.cardDetailsModal}>
            <View style={styles.cardDetailsHeader}>
              <Text style={styles.cardDetailsTitle}>Card Details</Text>
            </View>
            <View style={styles.cardDetailsBody}>
              <CardDetailRow label="Card name" value="Abdelahe Bouguelaa" />
              <CardDetailRow label="Card number" value="4549 2406 4600 2461" />
              <CardDetailRow label="CVV" value="968" />
              <CardDetailRow label="Expiry date" value="10/32" />
              <CardDetailRow label="Billing address" value="651 N Broad Street, Middle..." />
              <CardDetailRow label="Zip code" value="19709" last />
              <TouchableOpacity activeOpacity={0.85} style={styles.aboutCardButton}>
                <Text style={styles.aboutCardText}>About this card</Text>
              </TouchableOpacity>
            </View>
          </View>
          <TouchableOpacity activeOpacity={0.85} style={styles.cardDetailsClose} onPress={() => setDetailsVisible(false)}>
            <X size={22} color="#344054" />
          </TouchableOpacity>
        </View>
      )}
    </View>
  );
};

const ReportsPage: React.FC = () => (
  <ScrollView style={styles.page} contentContainerStyle={styles.pageContent} showsVerticalScrollIndicator={false}>
    <View style={styles.sectionBlock}>
      <Text style={styles.sectionHeading}>Statements</Text>
      {['May 2026 statement', 'April 2026 statement', 'March 2026 statement'].map((label) => (
        <View key={label} style={styles.accountRow}>
          <View style={styles.softIcon}>
            <FileText size={21} color="#2f6fe4" />
          </View>
          <View style={styles.accountMeta}>
            <Text style={styles.accountName}>{label}</Text>
            <Text style={styles.accountSub}>Ready to download</Text>
          </View>
          <ChevronRight size={18} color="#798392" />
        </View>
      ))}
    </View>
  </ScrollView>
);

const GreyLogo: React.FC<{ light?: boolean; size?: 'normal' | 'large' }> = ({ light, size = 'normal' }) => (
  <View style={styles.logoRow}>
    <View style={[styles.logoMark, light && styles.logoMarkLight]}>
      <View style={[styles.logoCut, light && styles.logoCutLight]} />
    </View>
    <Text style={[styles.logoText, size === 'large' && styles.logoTextLarge, light && styles.logoTextLight]}>Grey</Text>
  </View>
);

const CurrencyStack: React.FC = () => (
  <View style={styles.currencyStack}>
    <View style={[styles.stackCoin, { backgroundColor: '#f04438' }]}>
      <Text style={styles.stackCoinText}>US</Text>
    </View>
    <View style={[styles.stackCoin, styles.stackCoinOverlap, { backgroundColor: '#20b486' }]}>
      <Text style={styles.stackCoinText}>T</Text>
    </View>
    <View style={[styles.stackCoin, styles.stackCoinOverlap2, { backgroundColor: '#2f6fe4' }]}>
      <Text style={styles.stackCoinText}>$</Text>
    </View>
  </View>
);

const ActionCircle: React.FC<{
  label: string;
  Icon: React.ComponentType<any>;
  onPress?: () => void;
}> = ({ label, Icon, onPress }) => (
  <TouchableOpacity activeOpacity={0.8} onPress={onPress} style={styles.actionCircleWrap}>
    <View style={styles.actionCircle}>
      <Icon size={24} color="#111827" />
    </View>
    <Text style={styles.actionCircleText}>{label}</Text>
  </TouchableOpacity>
);

const ActionTile: React.FC<{
  title: string;
  copy: string;
  tint: string;
  Icon: React.ComponentType<any>;
  wide?: boolean;
  onPress?: () => void;
}> = ({ title, copy, tint, Icon, wide, onPress }) => (
  <TouchableOpacity activeOpacity={0.85} onPress={onPress} style={[styles.actionTile, wide && styles.actionTileWide]}>
    <View style={[styles.actionTileIcon, { backgroundColor: tint }]}>
      <Icon size={29} color="#2f6fe4" />
    </View>
    <Text style={styles.actionTileTitle}>{title}</Text>
    <Text style={styles.actionTileCopy}>{copy}</Text>
  </TouchableOpacity>
);

const SetupCard: React.FC = () => (
  <View style={styles.setupCard}>
    <View style={styles.setupTextBlock}>
      <Text style={styles.setupTitle}>اكمل الاعداد</Text>
      <Text style={styles.setupCopy}>استخدم هذا الدليل لاكمال اعداد حسابك</Text>
    </View>
    <View style={styles.progressRing}>
      <View style={styles.progressGap} />
      <Text style={styles.progressText}>4/5</Text>
    </View>
    <TouchableOpacity activeOpacity={0.85} style={styles.setupButton}>
      <Text style={styles.setupButtonText}>إكمال الإعداد</Text>
    </TouchableOpacity>
  </View>
);

const CardRoundAction: React.FC<{
  label: string;
  Icon: React.ComponentType<any>;
  active?: boolean;
  outlined?: boolean;
  onPress?: () => void;
}> = ({ label, Icon, active, outlined, onPress }) => (
  <TouchableOpacity activeOpacity={0.85} onPress={onPress} style={styles.cardRoundWrap}>
    <View style={[styles.cardRound, active && styles.cardRoundActive, outlined && styles.cardRoundOutlined]}>
      <Icon size={20} color={active ? '#ffffff' : '#0f172a'} />
    </View>
    <Text style={styles.cardRoundText}>{label}</Text>
  </TouchableOpacity>
);

const CardDetailRow: React.FC<{ label: string; value: string; last?: boolean }> = ({ label, value, last }) => (
  <View style={[styles.cardDetailRow, last && styles.cardDetailRowLast]}>
    <Text style={styles.cardDetailLabel}>{label}</Text>
    <View style={styles.cardDetailValueWrap}>
      <Text style={styles.cardDetailValue}>{value}</Text>
      <View style={styles.copyGlyph}>
        <Copy size={18} color="#98a2b3" />
      </View>
    </View>
  </View>
);

const ManageRow: React.FC<{
  Icon: React.ComponentType<any>;
  label: string;
  danger?: boolean;
}> = ({ Icon, label, danger }) => (
  <TouchableOpacity activeOpacity={0.85} style={styles.manageRow}>
    <View style={[styles.manageIcon, danger && styles.manageIconDanger]}>
      <Icon size={21} color={danger ? '#e12d48' : '#1f2937'} />
    </View>
    <Text style={[styles.manageLabel, danger && styles.manageLabelDanger]}>{label}</Text>
    {!danger && <ChevronRight size={19} color="#111827" />}
  </TouchableOpacity>
);

const styles = StyleSheet.create({
  safeArea: {
    flex: 1,
    backgroundColor: '#f5edf4',
  },
  shell: {
    flex: 1,
    alignItems: 'center',
    backgroundColor: '#f5edf4',
  },
  appFrame: {
    flex: 1,
    width: '100%',
    maxWidth: 788,
    backgroundColor: '#f7f7fa',
    overflow: 'hidden',
    minHeight: isWeb ? ('100vh' as any) : undefined,
  },
  appFrameWide: {
    marginTop: isWeb ? 0 : undefined,
  },
  topBar: {
    height: 64,
    backgroundColor: '#ffffff',
    borderBottomWidth: 1,
    borderBottomColor: '#edf0f4',
    paddingHorizontal: 18,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    zIndex: 3,
  },
  topTitleRow: {
    minWidth: 0,
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
  },
  topTitle: {
    color: '#10131b',
    fontSize: 20,
    fontWeight: '800',
    letterSpacing: 0,
  },
  handWave: {
    fontSize: 18,
  },
  topTools: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  languagePill: {
    height: 38,
    paddingHorizontal: 13,
    borderRadius: 19,
    backgroundColor: '#ffffff',
    borderWidth: 1,
    borderColor: '#edf0f4',
    flexDirection: 'row',
    alignItems: 'center',
    marginRight: 10,
  },
  languageText: {
    color: '#111827',
    fontSize: 14,
    fontWeight: '600',
    marginRight: 6,
  },
  avatar: {
    width: 34,
    height: 34,
    borderRadius: 17,
    backgroundColor: '#e2e7ef',
    alignItems: 'center',
    justifyContent: 'center',
    marginRight: 12,
  },
  avatarText: {
    color: '#222834',
    fontWeight: '800',
    fontSize: 14,
  },
  menuButton: {
    width: 34,
    height: 34,
    alignItems: 'center',
    justifyContent: 'center',
  },
  backButton: {
    width: 28,
    height: 28,
    justifyContent: 'center',
    marginRight: 8,
  },
  page: {
    flex: 1,
    backgroundColor: '#f7f7fa',
  },
  pageContent: {
    paddingHorizontal: 18,
    paddingTop: 26,
    paddingBottom: 82,
  },
  balancePanel: {
    backgroundColor: '#ffffff',
    borderRadius: 16,
    borderWidth: 1,
    borderColor: '#edf0f4',
    paddingHorizontal: 18,
    paddingTop: 28,
    paddingBottom: 20,
    shadowColor: '#b7bdc8',
    shadowOpacity: 0.12,
    shadowRadius: 18,
    shadowOffset: { width: 0, height: 8 },
  },
  balanceTop: {
    flexDirection: width >= 700 ? 'row' : 'column',
    alignItems: width >= 700 ? 'center' : 'center',
    justifyContent: 'space-between',
  },
  balanceLabelRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: width >= 700 ? 'flex-start' : 'center',
  },
  balanceLabel: {
    color: '#8b93a1',
    fontSize: 14,
    fontWeight: '700',
    marginRight: 6,
  },
  currencyStack: {
    width: 57,
    height: 20,
    marginRight: 2,
  },
  stackCoin: {
    position: 'absolute',
    left: 0,
    width: 22,
    height: 22,
    borderRadius: 11,
    borderWidth: 2,
    borderColor: '#ffffff',
    alignItems: 'center',
    justifyContent: 'center',
  },
  stackCoinOverlap: {
    left: 17,
  },
  stackCoinOverlap2: {
    left: 34,
  },
  stackCoinText: {
    color: '#ffffff',
    fontSize: 8,
    fontWeight: '900',
  },
  amountRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: width >= 700 ? 'flex-start' : 'center',
    marginTop: 5,
  },
  totalAmount: {
    color: '#111827',
    fontSize: 34,
    fontWeight: '900',
    letterSpacing: 0,
  },
  syncMini: {
    width: 28,
    height: 28,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: '#afc7ee',
    alignItems: 'center',
    justifyContent: 'center',
    marginLeft: 8,
  },
  mainActions: {
    flexDirection: 'row',
    justifyContent: 'center',
    marginTop: width >= 700 ? 0 : 28,
  },
  actionCircleWrap: {
    alignItems: 'center',
    marginHorizontal: width >= 700 ? 17 : 12,
  },
  actionCircle: {
    width: 57,
    height: 57,
    borderRadius: 29,
    backgroundColor: '#ffffff',
    borderWidth: 1,
    borderColor: '#e3e8f0',
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: 8,
  },
  actionCircleText: {
    color: '#171923',
    fontSize: 14,
    fontWeight: '800',
  },
  panelDivider: {
    height: 1,
    backgroundColor: '#ecf0f4',
    marginVertical: 22,
  },
  sectionHeading: {
    color: '#10131b',
    fontSize: 16,
    fontWeight: '900',
    marginBottom: 16,
  },
  balanceCardsRow: {
    flexDirection: 'row',
    paddingBottom: 2,
  },
  currencyCard: {
    width: width >= 700 ? 267 : 218,
    height: 146,
    backgroundColor: '#ffffff',
    borderWidth: 1,
    borderColor: '#e4e8ef',
    borderRadius: 10,
    padding: 18,
    marginRight: 12,
    justifyContent: 'flex-end',
    overflow: 'hidden',
  },
  currencyBadge: {
    position: 'absolute',
    top: 18,
    left: 18,
    width: 34,
    height: 34,
    borderRadius: 17,
    alignItems: 'center',
    justifyContent: 'center',
  },
  currencyBadgeText: {
    color: '#2f6fe4',
    fontSize: 13,
    fontWeight: '900',
  },
  currencyName: {
    color: '#858d9b',
    fontSize: 14,
    fontWeight: '700',
    marginBottom: 4,
  },
  currencyAmount: {
    color: '#111827',
    fontSize: 30,
    fontWeight: '900',
  },
  currencyChevron: {
    position: 'absolute',
    right: 13,
    top: 58,
    width: 38,
    height: 38,
    borderRadius: 19,
    backgroundColor: '#f2f4f7',
    alignItems: 'center',
    justifyContent: 'center',
  },
  setupCard: {
    marginTop: 24,
    backgroundColor: '#dbe9ff',
    borderRadius: 12,
    borderWidth: 1,
    borderColor: '#c7dafa',
    padding: 18,
    minHeight: 143,
    overflow: 'hidden',
  },
  setupTextBlock: {
    paddingRight: 88,
  },
  setupTitle: {
    color: '#10131b',
    fontSize: 16,
    fontWeight: '900',
    textAlign: 'left',
  },
  setupCopy: {
    color: '#46556a',
    fontSize: 13,
    marginTop: 6,
    lineHeight: 20,
    textAlign: 'left',
  },
  progressRing: {
    position: 'absolute',
    top: 18,
    right: 18,
    width: 58,
    height: 58,
    borderRadius: 29,
    borderWidth: 7,
    borderColor: '#2f6fe4',
    alignItems: 'center',
    justifyContent: 'center',
  },
  progressGap: {
    position: 'absolute',
    top: -8,
    right: -8,
    width: 27,
    height: 27,
    backgroundColor: '#dbe9ff',
  },
  progressText: {
    color: '#1f2937',
    fontSize: 16,
    fontWeight: '900',
  },
  setupButton: {
    height: 47,
    borderRadius: 7,
    backgroundColor: '#2f6fe4',
    justifyContent: 'center',
    alignItems: 'center',
    marginTop: 24,
  },
  setupButtonText: {
    color: '#ffffff',
    fontSize: 14,
    fontWeight: '800',
  },
  sectionBlock: {
    marginTop: 26,
    backgroundColor: '#ffffff',
    borderRadius: 14,
    borderWidth: 1,
    borderColor: '#edf0f4',
    padding: 18,
  },
  quickRow: {
    flexDirection: 'row',
  },
  actionTile: {
    width: width >= 700 ? 270 : 228,
    minHeight: 174,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: '#e9edf3',
    backgroundColor: '#ffffff',
    padding: 18,
    marginRight: 14,
    overflow: 'hidden',
  },
  actionTileWide: {
    width: '100%',
    minHeight: 162,
    marginRight: 0,
    marginBottom: 18,
  },
  actionTileIcon: {
    width: 44,
    height: 44,
    borderRadius: 10,
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: 18,
  },
  actionTileTitle: {
    color: '#10131b',
    fontSize: 17,
    fontWeight: '900',
    marginBottom: 8,
  },
  actionTileCopy: {
    color: '#3f4654',
    fontSize: 14,
    lineHeight: 21,
    maxWidth: 260,
  },
  accountRow: {
    minHeight: 76,
    borderBottomWidth: 1,
    borderBottomColor: '#edf0f4',
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 14,
  },
  accountMeta: {
    flex: 1,
    marginLeft: 14,
  },
  accountName: {
    color: '#111827',
    fontSize: 15,
    fontWeight: '800',
  },
  accountSub: {
    color: '#8b93a1',
    fontSize: 12,
    marginTop: 4,
  },
  accountAmount: {
    color: '#111827',
    fontSize: 20,
    fontWeight: '900',
    marginRight: 12,
  },
  paymentsPanel: {
    backgroundColor: '#ffffff',
    borderRadius: 14,
    borderWidth: 1,
    borderColor: '#edf0f4',
    padding: 20,
  },
  transactionsContent: {
    paddingHorizontal: 4,
    paddingTop: 28,
    paddingBottom: 82,
  },
  recentTransactionsHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: 24,
    paddingHorizontal: 22,
  },
  recentTransactionsTitle: {
    color: '#030712',
    fontSize: 16,
    fontWeight: '900',
  },
  seeAllText: {
    color: '#064eff',
    fontSize: 14,
    fontWeight: '700',
  },
  filterRow: {
    flexDirection: 'row',
    justifyContent: 'flex-end',
    marginBottom: 18,
  },
  filterPill: {
    height: 42,
    borderRadius: 8,
    backgroundColor: '#ffffff',
    borderWidth: 1,
    borderColor: '#edf0f4',
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 14,
    marginLeft: 10,
  },
  filterText: {
    color: '#111827',
    fontSize: 14,
    fontWeight: '700',
    marginRight: 8,
  },
  tableCard: {
    backgroundColor: '#ffffff',
    borderRadius: 8,
    borderWidth: 1,
    borderColor: '#dbe2ee',
    overflow: 'hidden',
  },
  tableRow: {
    minHeight: 63,
    flexDirection: 'row',
    alignItems: 'center',
    borderBottomWidth: 1,
    borderBottomColor: '#edf0f4',
    paddingHorizontal: 20,
  },
  tableRowMuted: {
    backgroundColor: '#f5f6fa',
  },
  tableHeader: {
    minHeight: 44,
    backgroundColor: '#f4f4f7',
  },
  tableHeadText: {
    color: '#8190ad',
    fontSize: 12,
    fontWeight: '900',
  },
  tableCell: {
    color: '#17355f',
    fontSize: 14,
    fontWeight: '500',
  },
  tableCellStrong: {
    color: '#00112d',
    fontSize: 14,
    fontWeight: '600',
  },
  tableDate: {
    flex: 1.55,
  },
  tableAmount: {
    flex: 1.05,
  },
  tableType: {
    flex: 1,
  },
  tableDescription: {
    flex: 1.45,
  },
  tableStatus: {
    flex: 1.08,
    alignItems: 'flex-start',
  },
  tableChevronCol: {
    width: 36,
    alignItems: 'flex-end',
  },
  statusPill: {
    height: 29,
    borderRadius: 15,
    borderWidth: 1,
    borderColor: '#edf0f4',
    backgroundColor: '#ffffff',
    paddingHorizontal: 10,
    flexDirection: 'row',
    alignItems: 'center',
  },
  statusDot: {
    width: 6,
    height: 6,
    borderRadius: 3,
    marginRight: 4,
  },
  statusDotProcessing: {
    backgroundColor: '#f59e0b',
  },
  statusDotCompleted: {
    backgroundColor: '#039855',
  },
  statusText: {
    fontSize: 12,
    fontWeight: '700',
  },
  statusTextProcessing: {
    color: '#d97706',
  },
  statusTextCompleted: {
    color: '#027a48',
  },
  cardPageHost: {
    flex: 1,
    backgroundColor: '#f7f7fa',
  },
  cardLabel: {
    color: '#7c8492',
    fontSize: 20,
    fontWeight: '800',
    fontStyle: 'italic',
    textAlign: 'center',
    marginBottom: 38,
  },
  editPencil: {
    color: '#111827',
    fontSize: 14,
    fontStyle: 'normal',
  },
  visaCard: {
    alignSelf: 'center',
    width: '100%',
    maxWidth: 350,
    aspectRatio: 1.58,
    borderRadius: 11,
    backgroundColor: '#0b1220',
    padding: 24,
    overflow: 'hidden',
    shadowColor: '#173a72',
    shadowOpacity: 0.28,
    shadowRadius: 28,
    shadowOffset: { width: 0, height: 18 },
  },
  visaCardFrozen: {
    opacity: 0.62,
  },
  cardWaveOne: {
    position: 'absolute',
    width: 260,
    height: 155,
    borderRadius: 90,
    backgroundColor: '#162843',
    opacity: 0.72,
    right: -74,
    top: 40,
    transform: [{ rotate: '-12deg' }],
  },
  cardWaveTwo: {
    position: 'absolute',
    width: 190,
    height: 130,
    borderRadius: 80,
    backgroundColor: '#30206d',
    opacity: 0.65,
    right: -28,
    bottom: -42,
  },
  cardWaveThree: {
    position: 'absolute',
    width: 220,
    height: 76,
    borderRadius: 38,
    backgroundColor: '#111827',
    opacity: 0.55,
    left: -54,
    top: 20,
    transform: [{ rotate: '-9deg' }],
  },
  cardTopRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
  },
  visaTextWrap: {
    alignItems: 'flex-end',
  },
  visaText: {
    color: '#ffffff',
    fontSize: 33,
    fontWeight: '900',
    fontStyle: 'italic',
    letterSpacing: 0,
  },
  visaSub: {
    color: '#ffffff',
    fontSize: 12,
    marginTop: -5,
  },
  cardNumber: {
    position: 'absolute',
    left: 24,
    bottom: 24,
    color: '#ffffff',
    fontSize: 21,
    fontWeight: '900',
  },
  cardActionRow: {
    marginTop: 40,
    flexDirection: 'row',
    justifyContent: 'center',
  },
  cardRoundWrap: {
    alignItems: 'center',
    marginHorizontal: 18,
  },
  cardRound: {
    width: 55,
    height: 55,
    borderRadius: 28,
    backgroundColor: '#ffffff',
    borderWidth: 1,
    borderColor: '#dfe4ec',
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: 8,
  },
  cardRoundActive: {
    backgroundColor: '#071b43',
    borderColor: '#071b43',
  },
  cardRoundOutlined: {
    borderColor: '#2f6fe4',
    borderWidth: 2,
  },
  cardRoundText: {
    color: '#111827',
    fontSize: 14,
    fontWeight: '800',
  },
  cardDetailsOverlay: {
    ...StyleSheet.absoluteFillObject,
    zIndex: 20,
    paddingTop: 26,
    paddingHorizontal: 30,
  },
  cardDetailsScrim: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: 'rgba(63, 78, 106, 0.62)',
  },
  cardDetailsModal: {
    width: '100%',
    maxWidth: 440,
    borderRadius: 11,
    backgroundColor: '#ffffff',
    overflow: 'hidden',
    shadowColor: '#111827',
    shadowOpacity: 0.18,
    shadowRadius: 22,
    shadowOffset: { width: 0, height: 14 },
  },
  cardDetailsHeader: {
    height: 61,
    borderBottomWidth: 1,
    borderBottomColor: '#d7dde8',
    justifyContent: 'center',
    paddingHorizontal: 28,
  },
  cardDetailsTitle: {
    color: '#00112d',
    fontSize: 20,
    fontWeight: '900',
  },
  cardDetailsBody: {
    paddingHorizontal: 20,
    paddingTop: 18,
    paddingBottom: 20,
  },
  cardDetailRow: {
    minHeight: 65,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 8,
  },
  cardDetailRowLast: {
    marginBottom: 14,
  },
  cardDetailLabel: {
    color: '#233b62',
    fontSize: 14,
    fontWeight: '800',
  },
  cardDetailValueWrap: {
    flex: 1,
    marginLeft: 18,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'flex-end',
  },
  cardDetailValue: {
    color: '#00112d',
    fontSize: 16,
    fontWeight: '600',
    textAlign: 'right',
    flexShrink: 1,
  },
  copyGlyph: {
    width: 30,
    height: 30,
    marginLeft: 18,
    alignItems: 'center',
    justifyContent: 'center',
  },
  aboutCardButton: {
    height: 49,
    borderRadius: 6,
    backgroundColor: '#2f6fe4',
    alignItems: 'center',
    justifyContent: 'center',
  },
  aboutCardText: {
    color: '#ffffff',
    fontSize: 14,
    fontWeight: '900',
  },
  cardDetailsClose: {
    position: 'absolute',
    top: 26,
    left: Math.min(480, width - 48),
    width: 32,
    height: 32,
    borderRadius: 16,
    backgroundColor: '#ffffff',
    alignItems: 'center',
    justifyContent: 'center',
  },
  walletStrip: {
    alignSelf: 'center',
    width: '100%',
    maxWidth: 366,
    minHeight: 69,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: '#e3e8f0',
    backgroundColor: '#ffffff',
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    marginTop: 32,
  },
  walletIconStack: {
    width: 48,
    height: 30,
    marginRight: 14,
  },
  walletMini: {
    position: 'absolute',
    top: 5,
    left: 0,
    width: 26,
    height: 20,
    borderRadius: 5,
    borderWidth: 2,
    borderColor: '#ffffff',
  },
  walletCopy: {
    flex: 1,
  },
  walletTitle: {
    color: '#111827',
    fontSize: 14,
    fontWeight: '900',
  },
  walletDesc: {
    color: '#818a98',
    fontSize: 13,
    marginTop: 3,
  },
  manageHeading: {
    color: '#525d6d',
    fontSize: 13,
    fontWeight: '900',
    marginTop: 42,
    marginBottom: 10,
  },
  manageList: {
    borderTopWidth: 1,
    borderTopColor: '#edf0f4',
  },
  manageRow: {
    minHeight: 72,
    flexDirection: 'row',
    alignItems: 'center',
  },
  manageIcon: {
    width: 39,
    height: 39,
    borderRadius: 20,
    backgroundColor: '#f1f3f6',
    alignItems: 'center',
    justifyContent: 'center',
    marginRight: 14,
  },
  manageIconDanger: {
    backgroundColor: '#fff0f3',
  },
  manageLabel: {
    flex: 1,
    color: '#4b5563',
    fontSize: 16,
    fontWeight: '800',
  },
  manageLabelDanger: {
    color: '#e12d48',
  },
  softIcon: {
    width: 42,
    height: 42,
    borderRadius: 21,
    backgroundColor: '#eef4ff',
    alignItems: 'center',
    justifyContent: 'center',
  },
  chatButton: {
    position: 'absolute',
    right: 22,
    bottom: 24,
    width: 54,
    height: 54,
    borderRadius: 27,
    backgroundColor: '#8ab8f7',
    alignItems: 'center',
    justifyContent: 'center',
    shadowColor: '#7aa7ee',
    shadowOpacity: 0.32,
    shadowRadius: 18,
    shadowOffset: { width: 0, height: 8 },
    zIndex: 6,
  },
  toast: {
    position: 'absolute',
    top: 76,
    right: 16,
    minHeight: 58,
    borderRadius: 8,
    backgroundColor: '#e7fff0',
    borderWidth: 1,
    borderColor: '#b7efc7',
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 14,
    zIndex: 8,
  },
  toastDot: {
    width: 17,
    height: 17,
    borderRadius: 9,
    backgroundColor: '#2fbd69',
    marginRight: 10,
  },
  toastText: {
    color: '#22663d',
    fontSize: 14,
    fontWeight: '900',
    marginRight: 12,
  },
  drawerLayer: {
    ...StyleSheet.absoluteFillObject,
    zIndex: 10,
  },
  drawerScrim: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: 'rgba(15,23,42,0.08)',
  },
  drawer: {
    position: 'absolute',
    left: 0,
    top: 0,
    bottom: 0,
    width: Math.min(255, width * 0.78),
    backgroundColor: '#ffffff',
    borderRightWidth: 1,
    borderRightColor: '#e5e9f0',
    paddingHorizontal: 16,
    paddingTop: 18,
    paddingBottom: 16,
    justifyContent: 'space-between',
    shadowColor: '#9aa3b2',
    shadowOpacity: 0.18,
    shadowRadius: 20,
    shadowOffset: { width: 12, height: 0 },
  },
  drawerLogoRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: 34,
  },
  drawerClose: {
    width: 32,
    height: 32,
    borderRadius: 16,
    alignItems: 'center',
    justifyContent: 'center',
  },
  logoRow: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  logoMark: {
    width: 23,
    height: 23,
    borderRadius: 6,
    backgroundColor: '#0b0f19',
    marginRight: 6,
    overflow: 'hidden',
  },
  logoMarkLight: {
    backgroundColor: '#ffffff',
  },
  logoCut: {
    position: 'absolute',
    width: 13,
    height: 13,
    borderRadius: 7,
    backgroundColor: '#ffffff',
    right: -2,
    top: 5,
  },
  logoCutLight: {
    backgroundColor: '#0b0f19',
  },
  logoText: {
    color: '#0b0f19',
    fontSize: 24,
    fontWeight: '900',
    letterSpacing: -0.2,
  },
  logoTextLarge: {
    fontSize: 30,
  },
  logoTextLight: {
    color: '#ffffff',
  },
  navList: {
    flex: 1,
  },
  navItem: {
    height: 43,
    borderRadius: 7,
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 10,
    marginBottom: 6,
  },
  navItemActive: {
    backgroundColor: '#e8f1ff',
  },
  navText: {
    color: '#737d8d',
    fontSize: 14,
    fontWeight: '700',
    marginLeft: 10,
  },
  navTextActive: {
    color: '#2468d8',
  },
  drawerBottom: {
    paddingBottom: 2,
  },
  communityRow: {
    flexDirection: 'row',
    alignItems: 'center',
    height: 44,
    paddingHorizontal: 10,
    marginBottom: 14,
  },
  communityText: {
    color: '#737d8d',
    fontSize: 14,
    fontWeight: '700',
    marginLeft: 10,
  },
  referralCard: {
    height: 143,
    borderRadius: 8,
    backgroundColor: '#00534e',
    padding: 18,
    overflow: 'hidden',
  },
  referralTitle: {
    color: '#ffffff',
    fontSize: 22,
    fontWeight: '900',
    lineHeight: 27,
    maxWidth: 176,
  },
  referralAmount: {
    color: '#e5ffe8',
    fontSize: 25,
    fontWeight: '900',
    marginTop: 2,
  },
  referralStripe: {
    position: 'absolute',
    width: 130,
    height: 28,
    borderRadius: 14,
    backgroundColor: '#8af0bb',
    right: -18,
    bottom: 24,
    transform: [{ rotate: '-25deg' }],
  },
});
