import React, { useState } from 'react';
import { StyleSheet, View, Text, SafeAreaView, TouchableOpacity, StatusBar, Platform, Dimensions } from 'react-native';
import { COLORS } from './src/theme/colors';
import { useAppStore } from './src/store/useAppStore';
import { OnboardingScreen } from './src/screens/OnboardingScreen';
import { AuthScreen } from './src/screens/AuthScreen';
import { DashboardScreen } from './src/screens/DashboardScreen';
import { VirtualCardScreen } from './src/screens/VirtualCardScreen';
import { TransferScreen } from './src/screens/TransferScreen';
import { ReceiveScreen } from './src/screens/ReceiveScreen';
import { AnalyticsScreen } from './src/screens/AnalyticsScreen';
import { KYCScreen } from './src/screens/KYCScreen';
import { SettingsScreen } from './src/screens/SettingsScreen';
import { AuditLogsScreen } from './src/screens/AuditLogsScreen';
import { translations } from './src/theme/translations';
import { Home, CreditCard, Send, BarChart2, ShieldCheck, ChevronLeft, Database } from 'lucide-react';

const { width, height } = Dimensions.get('window');
const isWeb = Platform.OS === 'web';

export default function App() {
  const { user, language } = useAppStore();
  const [appState, setAppState] = useState<'onboarding' | 'auth' | 'app'>('onboarding');
  const [activeTab, setActiveTab] = useState<'dashboard' | 'cards' | 'transfer' | 'analytics' | 'kyc' | 'receive' | 'settings' | 'logs'>('dashboard');

  const t = (key: string) => {
    return translations[language]?.[key] || translations['en']?.[key] || key;
  };

  const isRtl = language === 'ar';

  const renderActiveScreen = () => {
    switch (activeTab) {
      case 'dashboard':
        return <DashboardScreen onNavigate={(screen: any) => setActiveTab(screen)} />;
      case 'cards':
        return <VirtualCardScreen />;
      case 'transfer':
        return <TransferScreen />;
      case 'receive':
        return <ReceiveScreen />;
      case 'analytics':
        return <AnalyticsScreen />;
      case 'kyc':
        return <KYCScreen />;
      case 'logs':
        return <AuditLogsScreen />;
      case 'settings':
        return <SettingsScreen onLogout={() => setAppState('auth')} />;
      default:
        return <DashboardScreen onNavigate={(screen: any) => setActiveTab(screen)} />;
    }
  };

  const getScreenTitle = () => {
    switch (activeTab) {
      case 'receive': return t('RX_TITLE');
      case 'settings': return t('ST_TITLE');
      default: return '';
    }
  };

  // On Web, wrap the app inside a premium mobile emulator mock frame for incredible high-fidelity visual preview!
  const wrapWithFrame = (content: React.ReactNode) => {
    if (!isWeb) return content;

    return (
      <View style={[styles.webContainer, isRtl && styles.rtlRow]}>
        {/* Decorative background grid and text */}
        <View style={[styles.webPromoColumn, isRtl && styles.rtlAlign]}>
          <Text style={styles.promoTitle}>GRYE <Text style={{ color: COLORS.primary }}>ELITE</Text></Text>
          <Text style={[styles.promoDesc, isRtl && styles.rtlText]}>
            {isRtl 
              ? "اختبر معيارًا جديدًا للخدمات المصرفية الرقمية المظلمة والفاخرة. محاكاة كاملة مع تخزين الحالة، وتحويل العملات الفوري، وبطاقات فيزا الافتراضية، وسجلات العمليات المشفرة."
              : "Experience a new standard of dark luxury fintech neo-banking. Fully simulated with state storage, real-time conversions, virtual Visa cards, instant ledger histories, and biometric security features."}
          </Text>
          
          <View style={[styles.specBox, isRtl && styles.rtlRow]}>
            <View style={[styles.specDot, isRtl ? { marginLeft: 12 } : { marginRight: 12 }]} />
            <Text style={styles.specText}>
              {isRtl ? "واجهة Tailwind NativeWind و Reanimated جاهزة" : "Tailwind NativeWind & Reanimated structures ready"}
            </Text>
          </View>
          <View style={[styles.specBox, isRtl && styles.rtlRow]}>
            <View style={[styles.specDot, isRtl ? { marginLeft: 12 } : { marginRight: 12 }]} />
            <Text style={styles.specText}>
              {isRtl ? "دفتر أستاذ آمن ومحمي عبر قاعدة بيانات Firestore" : "Firestore secure data ledger structure"}
            </Text>
          </View>
          <View style={[styles.specBox, isRtl && styles.rtlRow]}>
            <View style={[styles.specDot, isRtl ? { marginLeft: 12 } : { marginRight: 12 }]} />
            <Text style={styles.specText}>
              {isRtl ? "بوابات دفع مجهزة بالكامل للربط مع Stripe" : "Stripe gateway ready payment channels"}
            </Text>
          </View>
        </View>

        {/* Dynamic Mobile Simulator Frame */}
        <View style={styles.phoneFrame}>
          <View style={styles.phoneNotch}>
            <View style={styles.notchCamera} />
            <View style={styles.notchSpeaker} />
          </View>
          <View style={styles.phoneScreen}>
            {content}
          </View>
        </View>
      </View>
    );
  };

  if (appState === 'onboarding') {
    return wrapWithFrame(
      <SafeAreaView style={styles.safeArea}>
        <StatusBar barStyle="light-content" />
        <OnboardingScreen onFinish={() => setAppState('auth')} />
      </SafeAreaView>
    );
  }

  if (appState === 'auth') {
    return wrapWithFrame(
      <SafeAreaView style={styles.safeArea}>
        <StatusBar barStyle="light-content" />
        <AuthScreen onSuccess={() => setAppState('app')} />
      </SafeAreaView>
    );
  }

  return wrapWithFrame(
    <SafeAreaView style={styles.safeArea}>
      <StatusBar barStyle="light-content" />
      
      {/* Sub-flow header back button */}
      {(activeTab === 'receive' || activeTab === 'settings') && (
        <View style={[styles.subHeader, isRtl && styles.rtlRow]}>
          <TouchableOpacity onPress={() => setActiveTab('dashboard')} style={[styles.backBtn, isRtl && styles.rtlRow]}>
            <View style={isRtl ? { transform: [{ rotate: '180deg' }] } : undefined}>
              <ChevronLeft size={20} color="#FFF" />
            </View>
            <Text style={[styles.backBtnText, isRtl ? { marginRight: 4 } : { marginLeft: 4 }]}>{t('BACK')}</Text>
          </TouchableOpacity>
          <Text style={styles.subHeaderTitle}>{getScreenTitle()}</Text>
          <View style={{ width: 60 }} />
        </View>
      )}

      {/* Primary Screen Render */}
      <View style={styles.screenWrapper}>
        {renderActiveScreen()}
      </View>

      {/* Premium Glassmorphic Bottom Navigation Bar */}
      {activeTab !== 'receive' && activeTab !== 'settings' && (
        <View style={[styles.tabBar, isRtl && styles.rtlRow]}>
          <TouchableOpacity 
            onPress={() => setActiveTab('dashboard')} 
            style={[styles.tabItem, activeTab === 'dashboard' && styles.tabItemActive]}
          >
            <Home size={20} color={activeTab === 'dashboard' ? COLORS.primary : COLORS.textSecondary} />
            <Text style={[styles.tabLabel, activeTab === 'dashboard' && styles.tabLabelActive]}>{t('NAV_HOME')}</Text>
          </TouchableOpacity>

          <TouchableOpacity 
            onPress={() => setActiveTab('cards')} 
            style={[styles.tabItem, activeTab === 'cards' && styles.tabItemActive]}
          >
            <CreditCard size={20} color={activeTab === 'cards' ? COLORS.primary : COLORS.textSecondary} />
            <Text style={[styles.tabLabel, activeTab === 'cards' && styles.tabLabelActive]}>{t('NAV_CARDS')}</Text>
          </TouchableOpacity>

          <TouchableOpacity 
            onPress={() => setActiveTab('transfer')} 
            style={[styles.tabItem, activeTab === 'transfer' && styles.tabItemActive]}
          >
            <Send size={20} color={activeTab === 'transfer' ? COLORS.primary : COLORS.textSecondary} />
            <Text style={[styles.tabLabel, activeTab === 'transfer' && styles.tabLabelActive]}>{t('NAV_SEND')}</Text>
          </TouchableOpacity>

          <TouchableOpacity 
            onPress={() => setActiveTab('analytics')} 
            style={[styles.tabItem, activeTab === 'analytics' && styles.tabItemActive]}
          >
            <BarChart2 size={20} color={activeTab === 'analytics' ? COLORS.primary : COLORS.textSecondary} />
            <Text style={[styles.tabLabel, activeTab === 'analytics' && styles.tabLabelActive]}>{t('NAV_REPORTS')}</Text>
          </TouchableOpacity>

          <TouchableOpacity 
            onPress={() => setActiveTab('logs')} 
            style={[styles.tabItem, activeTab === 'logs' && styles.tabItemActive]}
          >
            <Database size={20} color={activeTab === 'logs' ? COLORS.primary : COLORS.textSecondary} />
            <Text style={[styles.tabLabel, activeTab === 'logs' && styles.tabLabelActive]}>{t('NAV_LOGS')}</Text>
          </TouchableOpacity>

          <TouchableOpacity 
            onPress={() => setActiveTab('kyc')} 
            style={[styles.tabItem, activeTab === 'kyc' && styles.tabItemActive]}
          >
            <ShieldCheck size={20} color={activeTab === 'kyc' ? COLORS.primary : COLORS.textSecondary} />
            <Text style={[styles.tabLabel, activeTab === 'kyc' && styles.tabLabelActive]}>{t('NAV_KYC')}</Text>
          </TouchableOpacity>
        </View>
      )}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safeArea: {
    flex: 1,
    backgroundColor: COLORS.background,
  },
  screenWrapper: {
    flex: 1,
  },
  subHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingVertical: 14,
    backgroundColor: 'rgba(255,255,255,0.01)',
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(255,255,255,0.04)',
    marginTop: Platform.OS === 'ios' ? 40 : 0,
  },
  backBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    width: 80,
  },
  backBtnText: {
    color: '#FFF',
    fontSize: 13,
    fontWeight: '700',
  },
  subHeaderTitle: {
    color: '#FFF',
    fontSize: 12,
    fontWeight: '900',
    letterSpacing: 2,
  },
  tabBar: {
    flexDirection: 'row',
    backgroundColor: 'rgba(18, 18, 23, 0.95)',
    borderColor: 'rgba(255, 255, 255, 0.05)',
    borderTopWidth: 1,
    height: 72,
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    paddingBottom: Platform.OS === 'ios' ? 15 : 5,
    justifyContent: 'space-around',
    alignItems: 'center',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: -10 },
    shadowOpacity: 0.35,
    shadowRadius: 20,
    elevation: 8,
  },
  tabItem: {
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 8,
    paddingVertical: 6,
    borderRadius: 12,
    flex: 1,
  },
  tabItemActive: {
    backgroundColor: 'rgba(0, 255, 102, 0.02)',
  },
  tabLabel: {
    color: COLORS.textSecondary,
    fontSize: 8,
    fontWeight: '700',
    marginTop: 4,
  },
  tabLabelActive: {
    color: COLORS.primary,
    fontWeight: '900',
  },
  
  // Web specific mobile frame layout style
  webContainer: {
    flex: 1,
    flexDirection: 'row',
    backgroundColor: '#050507',
    alignItems: 'center',
    justifyContent: 'center',
    height: Platform.OS === 'web' ? '100vh' as any : '100%',
    width: Platform.OS === 'web' ? '100vw' as any : '100%',
    overflow: 'hidden',
  },
  webPromoColumn: {
    width: 450,
    paddingRight: 60,
    display: Platform.OS === 'web' ? 'flex' : 'none',
    flexDirection: 'column',
    justifyContent: 'center',
  },
  promoTitle: {
    color: '#FFF',
    fontSize: 48,
    fontWeight: '900',
    letterSpacing: 10,
    marginBottom: 20,
  },
  promoDesc: {
    color: COLORS.textSecondary,
    fontSize: 16,
    lineHeight: 28,
    marginBottom: 40,
  },
  specBox: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 16,
  },
  specDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: COLORS.primary,
  },
  specText: {
    color: '#FFF',
    fontSize: 14,
    fontWeight: '600',
  },
  phoneFrame: {
    width: 390,
    height: 812,
    borderRadius: 48,
    backgroundColor: '#000000',
    padding: 12,
    borderWidth: 6,
    borderColor: '#E4E4E7',
    position: 'relative',
    shadowColor: '#FFFFFF',
    shadowOffset: { width: 0, height: 20 },
    shadowOpacity: 0.08,
    shadowRadius: 60,
    elevation: 20,
  },
  phoneNotch: {
    position: 'absolute',
    top: 12,
    left: '50%',
    transform: [{ translateX: -70 }],
    width: 140,
    height: 30,
    backgroundColor: '#000',
    borderBottomLeftRadius: 18,
    borderBottomRightRadius: 18,
    zIndex: 100,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
  },
  notchCamera: {
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: '#1C1C21',
    marginRight: 20,
  },
  notchSpeaker: {
    width: 44,
    height: 4,
    borderRadius: 2,
    backgroundColor: '#1C1C21',
  },
  phoneScreen: {
    flex: 1,
    borderRadius: 36,
    overflow: 'hidden',
    backgroundColor: COLORS.background,
  },
  
  // RTL Utilities
  rtlRow: {
    flexDirection: 'row-reverse',
  },
  rtlAlign: {
    alignItems: 'flex-end',
  },
  rtlText: {
    textAlign: 'right',
  }
});
