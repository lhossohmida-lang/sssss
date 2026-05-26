import React, { useState } from 'react';
import { View, Text, StyleSheet, ScrollView, TouchableOpacity, Switch, Platform } from 'react-native';
import { COLORS } from '../theme/colors';
import { useAppStore } from '../store/useAppStore';
import { GlassCard } from '../components/GlassCard';
import { User, Lock, Bell, Shield, Languages, Laptop, LogOut, ChevronRight, Award } from 'lucide-react';

interface SettingsScreenProps {
  onLogout: () => void;
}

export const SettingsScreen: React.FC<SettingsScreenProps> = ({ onLogout }) => {
  const { 
    theme, setTheme, 
    language, setLanguage, 
    notificationsEnabled, toggleNotifications, 
    user, resetAll 
  } = useAppStore();

  const [useBiometrics, setUseBiometrics] = useState(true);

  const handleLogout = () => {
    resetAll();
    onLogout();
    alert('Logged out from all secure JWT sessions.');
  };

  return (
    <ScrollView style={styles.container} showsVerticalScrollIndicator={false}>
      <View style={styles.header}>
        <Text style={styles.title}>SETTINGS</Text>
        <Text style={styles.subtitle}>Configure your security profile & preferences</Text>
      </View>

      {/* User profile head */}
      <GlassCard glowing={true} style={styles.profileBox}>
        <View style={styles.profileMeta}>
          <View style={styles.profileAvatar}>
            <Text style={styles.avatarText}>AM</Text>
          </View>
          <View style={{ marginLeft: 15 }}>
            <Text style={styles.profileName}>{user?.fullName || 'Alexander Moreau'}</Text>
            <Text style={styles.profileEmail}>{user?.email || 'alex.moreau@grye-premium.com'}</Text>
            <View style={styles.premiumTag}>
              <Award size={12} color={COLORS.primary} style={{ marginRight: 4 }} />
              <Text style={styles.premiumTagText}>ELITE VIP PLATINUM</Text>
            </View>
          </View>
        </View>
      </GlassCard>

      {/* Preferences Section */}
      <Text style={styles.sectionTitle}>App Preferences</Text>
      
      <GlassCard style={styles.settingsGroup}>
        {/* Theme Toggle */}
        <View style={styles.settingsItem}>
          <View style={styles.settingsLeft}>
            <View style={styles.iconWrapper}>
              <Shield size={18} color={COLORS.primary} />
            </View>
            <Text style={styles.settingsLabel}>Dark Mode Luxury Aesthetics</Text>
          </View>
          <Switch 
            value={theme === 'dark'} 
            onValueChange={(val) => setTheme(val ? 'dark' : 'light')}
            trackColor={{ false: '#3F3F46', true: COLORS.primaryGlow }}
            thumbColor={theme === 'dark' ? COLORS.primary : '#F4F4F5'}
          />
        </View>

        {/* Push notifications */}
        <View style={[styles.settingsItem, styles.borderTop]}>
          <View style={styles.settingsLeft}>
            <View style={styles.iconWrapper}>
              <Bell size={18} color={COLORS.primary} />
            </View>
            <Text style={styles.settingsLabel}>FCM Push Notifications</Text>
          </View>
          <Switch 
            value={notificationsEnabled} 
            onValueChange={toggleNotifications}
            trackColor={{ false: '#3F3F46', true: COLORS.primaryGlow }}
            thumbColor={notificationsEnabled ? COLORS.primary : '#F4F4F5'}
          />
        </View>

        {/* Biometrics */}
        <View style={[styles.settingsItem, styles.borderTop]}>
          <View style={styles.settingsLeft}>
            <View style={styles.iconWrapper}>
              <Lock size={18} color={COLORS.primary} />
            </View>
            <Text style={styles.settingsLabel}>Face ID / Biometric Lock</Text>
          </View>
          <Switch 
            value={useBiometrics} 
            onValueChange={setUseBiometrics}
            trackColor={{ false: '#3F3F46', true: COLORS.primaryGlow }}
            thumbColor={useBiometrics ? COLORS.primary : '#F4F4F5'}
          />
        </View>
      </GlassCard>

      {/* Language system */}
      <Text style={styles.sectionTitle}>Language System</Text>
      <GlassCard style={styles.settingsGroup}>
        <View style={styles.langGrid}>
          {[
            { code: 'en', label: 'English' },
            { code: 'es', label: 'Español' },
            { code: 'fr', label: 'Français' },
            { code: 'de', label: 'Deutsch' },
          ].map((lang) => (
            <TouchableOpacity 
              key={lang.code}
              onPress={() => setLanguage(lang.code as any)}
              style={[
                styles.langBtn,
                language === lang.code && styles.langBtnActive
              ]}
            >
              <Text style={[
                styles.langBtnText,
                language === lang.code && styles.langBtnTextActive
              ]}>
                {lang.label}
              </Text>
            </TouchableOpacity>
          ))}
        </View>
      </GlassCard>

      {/* Device Management */}
      <Text style={styles.sectionTitle}>Connected Devices</Text>
      <GlassCard style={styles.settingsGroup}>
        <View style={styles.deviceItem}>
          <Laptop size={20} color={COLORS.primary} style={{ marginRight: 15 }} />
          <View style={{ flex: 1 }}>
            <Text style={styles.deviceName}>Apple iPhone 15 Pro Max (This Device)</Text>
            <Text style={styles.deviceMeta}>Active Session • London, UK</Text>
          </View>
          <ChevronRight size={16} color="rgba(255,255,255,0.3)" />
        </View>
      </GlassCard>

      {/* Logout Action button */}
      <TouchableOpacity onPress={handleLogout} style={styles.logoutBtn}>
        <LogOut size={18} color="#EF4444" style={{ marginRight: 8 }} />
        <Text style={styles.logoutText}>TERMINATE JWT SESSIONS & LOGOUT</Text>
      </TouchableOpacity>

      <View style={{ height: 100 }} />
    </ScrollView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: COLORS.background,
    paddingHorizontal: 16,
    paddingTop: 20,
  },
  header: {
    marginBottom: 20,
    marginTop: Platform.OS === 'ios' ? 40 : 10,
  },
  title: {
    color: '#FFF',
    fontSize: 22,
    fontWeight: '900',
    letterSpacing: 3,
  },
  subtitle: {
    color: COLORS.textSecondary,
    fontSize: 12,
    marginTop: 4,
  },
  profileBox: {
    padding: 20,
    marginBottom: 30,
  },
  profileMeta: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  profileAvatar: {
    width: 60,
    height: 60,
    borderRadius: 30,
    backgroundColor: 'rgba(0, 255, 102, 0.08)',
    borderColor: 'rgba(0, 255, 102, 0.2)',
    borderWidth: 1.5,
    justifyContent: 'center',
    alignItems: 'center',
  },
  avatarText: {
    color: COLORS.primary,
    fontSize: 18,
    fontWeight: '900',
  },
  profileName: {
    color: '#FFF',
    fontSize: 16,
    fontWeight: '800',
  },
  profileEmail: {
    color: COLORS.textSecondary,
    fontSize: 12,
    marginTop: 2,
  },
  premiumTag: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: 'rgba(0, 255, 102, 0.05)',
    paddingHorizontal: 6,
    paddingVertical: 3,
    borderRadius: 6,
    marginTop: 6,
    alignSelf: 'flex-start',
  },
  premiumTagText: {
    color: COLORS.primary,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 1,
  },
  sectionTitle: {
    color: '#FFF',
    fontSize: 15,
    fontWeight: '800',
    marginBottom: 16,
    letterSpacing: 1.5,
  },
  settingsGroup: {
    padding: 10,
    marginBottom: 24,
  },
  settingsItem: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: 14,
    paddingHorizontal: 10,
  },
  borderTop: {
    borderTopWidth: 1,
    borderTopColor: 'rgba(255,255,255,0.04)',
  },
  settingsLeft: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  iconWrapper: {
    width: 32,
    height: 32,
    borderRadius: 10,
    backgroundColor: 'rgba(255,255,255,0.03)',
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 12,
  },
  settingsLabel: {
    color: '#FFF',
    fontSize: 12,
    fontWeight: '700',
  },
  langGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    padding: 6,
  },
  langBtn: {
    flex: 1,
    minWidth: '45%',
    backgroundColor: 'rgba(255,255,255,0.01)',
    borderColor: 'rgba(255,255,255,0.04)',
    borderWidth: 1,
    borderRadius: 10,
    paddingVertical: 10,
    alignItems: 'center',
    margin: 4,
  },
  langBtnActive: {
    backgroundColor: 'rgba(0, 255, 102, 0.08)',
    borderColor: 'rgba(0, 255, 102, 0.2)',
  },
  langBtnText: {
    color: COLORS.textSecondary,
    fontSize: 11,
    fontWeight: '700',
  },
  langBtnTextActive: {
    color: COLORS.primary,
  },
  deviceItem: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: 12,
  },
  deviceName: {
    color: '#FFF',
    fontSize: 12,
    fontWeight: '700',
  },
  deviceMeta: {
    color: COLORS.textSecondary,
    fontSize: 10,
    marginTop: 2,
  },
  logoutBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    borderColor: 'rgba(239, 68, 68, 0.2)',
    borderWidth: 1,
    backgroundColor: 'rgba(239, 68, 68, 0.03)',
    height: 52,
    borderRadius: 14,
    marginTop: 10,
  },
  logoutText: {
    color: '#EF4444',
    fontSize: 11,
    fontWeight: '900',
    letterSpacing: 1.5,
  }
});
