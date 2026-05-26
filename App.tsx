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
import { Home, CreditCard, Send, BarChart2, ShieldCheck, ChevronLeft } from 'lucide-react';

const { width, height } = Dimensions.get('window');
const isWeb = Platform.OS === 'web';

export default function App() {
  const { user, setUser } = useAppStore();
  const [appState, setAppState] = useState<'onboarding' | 'auth' | 'app'>('onboarding');
  const [activeTab, setActiveTab] = useState<'dashboard' | 'cards' | 'transfer' | 'analytics' | 'kyc' | 'receive' | 'settings'>('dashboard');

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
      case 'settings':
        return <SettingsScreen onLogout={() => setAppState('auth')} />;
      default:
        return <DashboardScreen onNavigate={(screen: any) => setActiveTab(screen)} />;
    }
  };

  const getScreenTitle = () => {
    switch (activeTab) {
      case 'receive': return 'RECEIVE ASSETS';
      case 'settings': return 'PREFERENCES';
      default: return '';
    }
  };

  // On Web, wrap the app inside a premium mobile emulator mock frame for incredible high-fidelity visual preview!
  const wrapWithFrame = (content: React.ReactNode) => {
    if (!isWeb) return content;

    return (
      <View style={styles.webContainer}>
        {/* Decorative background grid and text */}
        <View style={styles.webPromoColumn}>
          <Text style={styles.promoTitle}>GRYE <Text style={{ color: COLORS.primary }}>ELITE</Text></Text>
          <Text style={styles.promoDesc}>
            Experience a new standard of dark luxury fintech neo-banking. 
            Fully simulated with state storage, real-time conversions, virtual Visa cards, 
            instant ledger histories, and biometric security features.
          </Text>
          
          <View style={styles.specBox}>
            <View style={styles.specDot} />
            <Text style={styles.specText}>Tailwind NativeWind & Reanimated structures ready</Text>
          </View>
          <View style={styles.specBox}>
            <View style={styles.specDot} />
            <Text style={styles.specText}>Firestore secure data ledger structure</Text>
          </View>
          <View style={styles.specBox}>
            <View style={styles.specDot} />
            <Text style={styles.specText}>Stripe gateway ready payment channels</Text>
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
        <View style={styles.subHeader}>
          <TouchableOpacity onPress={() => setActiveTab('dashboard')} style={styles.backBtn}>
            <ChevronLeft size={20} color="#FFF" />
            <Text style={styles.backBtnText}>Back</Text>
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
        <View style={styles.tabBar}>
          <TouchableOpacity 
            onPress={() => setActiveTab('dashboard')} 
            style={[styles.tabItem, activeTab === 'dashboard' && styles.tabItemActive]}
          >
            <Home size={22} color={activeTab === 'dashboard' ? COLORS.primary : COLORS.textSecondary} />
            <Text style={[styles.tabLabel, activeTab === 'dashboard' && styles.tabLabelActive]}>Home</Text>
          </TouchableOpacity>

          <TouchableOpacity 
            onPress={() => setActiveTab('cards')} 
            style={[styles.tabItem, activeTab === 'cards' && styles.tabItemActive]}
          >
            <CreditCard size={22} color={activeTab === 'cards' ? COLORS.primary : COLORS.textSecondary} />
            <Text style={[styles.tabLabel, activeTab === 'cards' && styles.tabLabelActive]}>Cards</Text>
          </TouchableOpacity>

          <TouchableOpacity 
            onPress={() => setActiveTab('transfer')} 
            style={[styles.tabItem, activeTab === 'transfer' && styles.tabItemActive]}
          >
            <Send size={22} color={activeTab === 'transfer' ? COLORS.primary : COLORS.textSecondary} />
            <Text style={[styles.tabLabel, activeTab === 'transfer' && styles.tabLabelActive]}>Send</Text>
          </TouchableOpacity>

          <TouchableOpacity 
            onPress={() => setActiveTab('analytics')} 
            style={[styles.tabItem, activeTab === 'analytics' && styles.tabItemActive]}
          >
            <BarChart2 size={22} color={activeTab === 'analytics' ? COLORS.primary : COLORS.textSecondary} />
            <Text style={[styles.tabLabel, activeTab === 'analytics' && styles.tabLabelActive]}>Reports</Text>
          </TouchableOpacity>

          <TouchableOpacity 
            onPress={() => setActiveTab('kyc')} 
            style={[styles.tabItem, activeTab === 'kyc' && styles.tabItemActive]}
          >
            <ShieldCheck size={22} color={activeTab === 'kyc' ? COLORS.primary : COLORS.textSecondary} />
            <Text style={[styles.tabLabel, activeTab === 'kyc' && styles.tabLabelActive]}>KYC</Text>
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
    width: 60,
  },
  backBtnText: {
    color: '#FFF',
    fontSize: 13,
    fontWeight: '700',
    marginLeft: 4,
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
    paddingHorizontal: 14,
    paddingVertical: 6,
    borderRadius: 16,
  },
  tabItemActive: {
    backgroundColor: 'rgba(0, 255, 102, 0.03)',
  },
  tabLabel: {
    color: COLORS.textSecondary,
    fontSize: 9,
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
    marginRight: 12,
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
    backgroundColor: '#000',
    padding: 12,
    borderWidth: 8,
    borderColor: '#242429',
    position: 'relative',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 30 },
    shadowOpacity: 0.6,
    shadowRadius: 50,
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
  }
});
