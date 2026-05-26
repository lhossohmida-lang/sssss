import React, { useState } from 'react';
import { View, Text, StyleSheet, TextInput, TouchableOpacity, ActivityIndicator, Platform } from 'react-native';
import { COLORS } from '../theme/colors';
import { GlassCard } from '../components/GlassCard';
import { useAppStore } from '../store/useAppStore';
import { translations } from '../theme/translations';
import { Mail, Lock, User, ArrowRight, Smartphone } from 'lucide-react';

interface AuthScreenProps {
  onSuccess: () => void;
}

export const AuthScreen: React.FC<AuthScreenProps> = ({ onSuccess }) => {
  const { language } = useAppStore();
  const [isLogin, setIsLogin] = useState(true);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [name, setName] = useState('');
  const [phone, setPhone] = useState('');
  const [useOtp, setUseOtp] = useState(false);
  const [otpCode, setOtpCode] = useState('');
  const [otpSent, setOtpSent] = useState(false);
  
  const setUser = useAppStore((state) => state.setUser);
  const isLoading = useAppStore((state) => state.isLoading);
  const setLoading = useAppStore((state) => state.setLoading);

  const t = (key: string) => {
    return translations[language]?.[key] || translations['en']?.[key] || key;
  };

  const isRtl = language === 'ar';

  const handleAuth = async () => {
    if (!email || !password || (!isLogin && !name)) {
      alert(isRtl ? 'يرجى ملء جميع الحقول المطلوبة.' : 'Please fill out all fields.');
      return;
    }
    
    setLoading(true);
    // Simulate API delay & Firebase auth behavior
    setTimeout(() => {
      setLoading(false);
      setUser({
        uid: 'user_dev_001',
        email: email,
        fullName: isLogin ? 'Alexander Moreau' : name,
        phoneNumber: phone || '+1 (555) 019-2831',
        isPremium: true
      });
      onSuccess();
    }, 1500);
  };

  const handleOtpRequest = () => {
    if (!phone) {
      alert(isRtl ? 'يرجى إدخال رقم هاتف صالح.' : 'Please enter a valid phone number.');
      return;
    }
    setLoading(true);
    setTimeout(() => {
      setLoading(false);
      setOtpSent(true);
    }, 1000);
  };

  const handleOtpVerify = () => {
    if (otpCode.length < 4) {
      alert(isRtl ? 'أدخل الرمز الكامل المكون من 4 أرقام.' : 'Enter complete 4-digit code.');
      return;
    }
    setLoading(true);
    setTimeout(() => {
      setLoading(false);
      setUser({
        uid: 'user_dev_001',
        email: 'alex.moreau@grye-premium.com',
        fullName: 'Alexander Moreau',
        phoneNumber: phone,
        isPremium: true
      });
      onSuccess();
    }, 1200);
  };

  return (
    <View style={styles.container}>
      <View style={styles.radialGlow} />

      <View style={[styles.header, isRtl && styles.rtlAlign]}>
        <Text style={styles.title}>{t('AUTH_WELCOME')}</Text>
        <Text style={styles.subtitle}>{t('AUTH_SUBTITLE')}</Text>
      </View>

      <GlassCard glowing={true} style={styles.authBox}>
        {/* Sliding Tabs */}
        {!useOtp && (
          <View style={[styles.tabContainer, isRtl && styles.rtlRow]}>
            <TouchableOpacity 
              onPress={() => setIsLogin(true)} 
              style={[styles.tab, isLogin && styles.activeTab]}
            >
              <Text style={[styles.tabText, isLogin && styles.activeTabText]}>
                {t('AUTH_SIGN_IN')}
              </Text>
            </TouchableOpacity>
            <TouchableOpacity 
              onPress={() => setIsLogin(false)} 
              style={[styles.tab, !isLogin && styles.activeTab]}
            >
              <Text style={[styles.tabText, !isLogin && styles.activeTabText]}>
                {t('AUTH_REGISTER')}
              </Text>
            </TouchableOpacity>
          </View>
        )}

        {useOtp ? (
          // OTP Phone Verification Flow
          <View style={[styles.formContainer, isRtl && styles.rtlAlign]}>
            <Text style={styles.formTitle}>{t('AUTH_PHONE_TITLE')}</Text>
            <Text style={styles.formDesc}>{t('AUTH_PHONE_DESC')}</Text>

            {!otpSent ? (
              <View style={{ width: '100%' }}>
                <View style={[styles.inputWrapper, isRtl && styles.rtlRow]}>
                  <Smartphone size={20} color="rgba(255,255,255,0.4)" style={isRtl ? { marginLeft: 12 } : { marginRight: 12 }} />
                  <TextInput 
                    placeholder={t('AUTH_PHONE_PLACEHOLDER')} 
                    placeholderTextColor="rgba(255,255,255,0.3)"
                    style={[styles.input, isRtl && styles.rtlText]}
                    value={phone}
                    onChangeText={setPhone}
                    keyboardType="phone-pad"
                  />
                </View>
                <TouchableOpacity onPress={handleOtpRequest} style={styles.submitBtn}>
                  {isLoading ? (
                    <ActivityIndicator color="#000" />
                  ) : (
                    <Text style={styles.submitText}>{t('AUTH_PHONE_SUBMIT')}</Text>
                  )}
                </TouchableOpacity>
              </View>
            ) : (
              <View style={{ width: '100%' }}>
                <View style={[styles.inputWrapper, isRtl && styles.rtlRow]}>
                  <Lock size={20} color="rgba(255,255,255,0.4)" style={isRtl ? { marginLeft: 12 } : { marginRight: 12 }} />
                  <TextInput 
                    placeholder={t('AUTH_OTP_PLACEHOLDER')} 
                    placeholderTextColor="rgba(255,255,255,0.3)"
                    style={[styles.input, isRtl && styles.rtlText]}
                    value={otpCode}
                    onChangeText={setOtpCode}
                    keyboardType="numeric"
                    maxLength={4}
                  />
                </View>
                <TouchableOpacity onPress={handleOtpVerify} style={styles.submitBtn}>
                  {isLoading ? (
                    <ActivityIndicator color="#000" />
                  ) : (
                    <Text style={styles.submitText}>{t('AUTH_OTP_SUBMIT')}</Text>
                  )}
                </TouchableOpacity>
              </View>
            )}

            <TouchableOpacity onPress={() => { setUseOtp(false); setOtpSent(false); }} style={styles.backBtn}>
              <Text style={styles.backBtnText}>{t('AUTH_BACK_EMAIL')}</Text>
            </TouchableOpacity>
          </View>
        ) : (
          // Standard Email/Password Flow
          <View style={styles.formContainer}>
            {!isLogin && (
              <View style={[styles.inputWrapper, isRtl && styles.rtlRow]}>
                <User size={20} color="rgba(255,255,255,0.4)" style={isRtl ? { marginLeft: 12 } : { marginRight: 12 }} />
                <TextInput 
                  placeholder={t('AUTH_FULL_NAME')} 
                  placeholderTextColor="rgba(255,255,255,0.3)"
                  style={[styles.input, isRtl && styles.rtlText]}
                  value={name}
                  onChangeText={setName}
                />
              </View>
            )}

            <View style={[styles.inputWrapper, isRtl && styles.rtlRow]}>
              <Mail size={20} color="rgba(255,255,255,0.4)" style={isRtl ? { marginLeft: 12 } : { marginRight: 12 }} />
              <TextInput 
                placeholder={t('AUTH_EMAIL')} 
                placeholderTextColor="rgba(255,255,255,0.3)"
                style={[styles.input, isRtl && styles.rtlText]}
                value={email}
                onChangeText={setEmail}
                keyboardType="email-address"
                autoCapitalize="none"
              />
            </View>

            <View style={[styles.inputWrapper, isRtl && styles.rtlRow]}>
              <Lock size={20} color="rgba(255,255,255,0.4)" style={isRtl ? { marginLeft: 12 } : { marginRight: 12 }} />
              <TextInput 
                placeholder={t('AUTH_PASSWORD')} 
                placeholderTextColor="rgba(255,255,255,0.3)"
                style={[styles.input, isRtl && styles.rtlText]}
                secureTextEntry
                value={password}
                onChangeText={setPassword}
              />
            </View>

            <TouchableOpacity onPress={handleAuth} style={styles.submitBtn}>
              {isLoading ? (
                <ActivityIndicator color="#000" />
              ) : (
                <View style={[styles.btnContent, isRtl && styles.rtlRow]}>
                  <Text style={styles.submitText}>
                    {isLogin ? t('AUTH_SUBMIT_SIGNIN') : t('AUTH_SUBMIT_REGISTER')}
                  </Text>
                  <ArrowRight size={18} color="#000" style={isRtl ? { marginRight: 6 } : { marginLeft: 6 }} />
                </View>
              )}
            </TouchableOpacity>

            {/* Verification options */}
            <Text style={styles.dividerText}>{t('AUTH_OR')}</Text>

            <View style={styles.socialRow}>
              <TouchableOpacity onPress={() => setUseOtp(true)} style={[styles.socialBtn, { flex: 1, justifyContent: 'center' }]}>
                <Smartphone size={20} color="#FFF" style={{ marginRight: 6 }} />
                <Text style={styles.socialBtnText}>{t('AUTH_OTP_PHONE')}</Text>
              </TouchableOpacity>
            </View>
          </View>
        )}
      </GlassCard>

      <Text style={[styles.legalText, isRtl && styles.rtlText]}>
        {t('AUTH_LEGAL')}
      </Text>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: COLORS.background,
    justifyContent: 'center',
    paddingHorizontal: 24,
    paddingVertical: 40,
  },
  radialGlow: {
    position: 'absolute',
    bottom: -100,
    right: -100,
    width: 400,
    height: 400,
    borderRadius: 200,
    backgroundColor: 'rgba(255, 255, 255, 0.03)',
    filter: Platform.OS === 'web' ? 'blur(100px)' : undefined,
  } as any,
  header: {
    alignItems: 'center',
    marginBottom: 40,
  },
  title: {
    color: '#FFF',
    fontSize: 26,
    fontWeight: '900',
    letterSpacing: 4,
    textAlign: 'center',
  },
  subtitle: {
    color: COLORS.textSecondary,
    fontSize: 12,
    marginTop: 8,
    textAlign: 'center',
  },
  authBox: {
    padding: 24,
  },
  tabContainer: {
    flexDirection: 'row',
    backgroundColor: 'rgba(255,255,255,0.01)',
    borderColor: 'rgba(255,255,255,0.04)',
    borderWidth: 1,
    borderRadius: 12,
    padding: 4,
    marginBottom: 24,
  },
  tab: {
    flex: 1,
    paddingVertical: 10,
    alignItems: 'center',
    borderRadius: 8,
  },
  activeTab: {
    backgroundColor: COLORS.primary,
  },
  tabText: {
    color: COLORS.textSecondary,
    fontSize: 12,
    fontWeight: '800',
  },
  activeTabText: {
    color: '#000',
  },
  formContainer: {
    width: '100%',
  },
  formTitle: {
    color: '#FFF',
    fontSize: 18,
    fontWeight: '800',
    marginBottom: 4,
  },
  formDesc: {
    color: COLORS.textSecondary,
    fontSize: 12,
    marginBottom: 20,
  },
  inputWrapper: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: 'rgba(255, 255, 255, 0.02)',
    borderColor: 'rgba(255, 255, 255, 0.05)',
    borderWidth: 1,
    borderRadius: 14,
    paddingHorizontal: 16,
    marginBottom: 16,
    height: 52,
  },
  inputIcon: {
    marginRight: 12,
  },
  input: {
    flex: 1,
    color: '#FFF',
    fontSize: 14,
    height: '100%',
  },
  submitBtn: {
    backgroundColor: COLORS.primary,
    height: 52,
    borderRadius: 14,
    justifyContent: 'center',
    alignItems: 'center',
    marginTop: 10,
    shadowColor: COLORS.primary,
    shadowOffset: { width: 0, height: 6 },
    shadowOpacity: 0.15,
    shadowRadius: 10,
  },
  btnContent: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  submitText: {
    color: '#000',
    fontSize: 13,
    fontWeight: '900',
    letterSpacing: 2,
  },
  dividerText: {
    color: COLORS.textMuted,
    fontSize: 9,
    fontWeight: '900',
    textAlign: 'center',
    marginVertical: 20,
    letterSpacing: 1.5,
  },
  socialRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
  },
  socialBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: 'rgba(255,255,255,0.02)',
    borderColor: 'rgba(255,255,255,0.05)',
    borderWidth: 1,
    borderRadius: 12,
    paddingVertical: 12,
    paddingHorizontal: 16,
  },
  socialBtnText: {
    color: '#FFF',
    fontSize: 12,
    fontWeight: '700',
  },
  backBtn: {
    alignSelf: 'center',
    marginTop: 20,
  },
  backBtnText: {
    color: COLORS.textSecondary,
    fontSize: 12,
    fontWeight: '800',
  },
  legalText: {
    color: COLORS.textMuted,
    fontSize: 9,
    lineHeight: 14,
    textAlign: 'center',
    marginTop: 30,
    paddingHorizontal: 10,
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
