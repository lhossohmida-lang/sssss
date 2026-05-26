import React, { useState } from 'react';
import { View, Text, StyleSheet, TextInput, TouchableOpacity, ActivityIndicator, Platform } from 'react-native';
import { COLORS } from '../theme/colors';
import { GlassCard } from '../components/GlassCard';
import { useAppStore } from '../store/useAppStore';
import { Mail, Lock, User, ArrowRight, Smartphone, Fingerprint } from 'lucide-react';

interface AuthScreenProps {
  onSuccess: () => void;
}

export const AuthScreen: React.FC<AuthScreenProps> = ({ onSuccess }) => {
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

  const handleAuth = async () => {
    if (!email || !password || (!isLogin && !name)) {
      alert('Please fill out all fields.');
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
      alert('Please enter a valid phone number.');
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
      alert('Enter complete 4-digit code.');
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

  const handleBiometrics = () => {
    setLoading(true);
    setTimeout(() => {
      setLoading(false);
      setUser({
        uid: 'user_dev_001',
        email: 'alex.moreau@grye-premium.com',
        fullName: 'Alexander Moreau',
        phoneNumber: '+1 (555) 019-2831',
        isPremium: true
      });
      onSuccess();
    }, 800);
  };

  return (
    <View style={styles.container}>
      <View style={styles.radialGlow} />

      <View style={styles.header}>
        <Text style={styles.title}>WELCOME TO GRYE</Text>
        <Text style={styles.subtitle}>Enter the circle of elite luxury banking</Text>
      </View>

      <GlassCard glowing={true} style={styles.authBox}>
        {/* Sliding Tabs */}
        {!useOtp && (
          <View style={styles.tabContainer}>
            <TouchableOpacity 
              onPress={() => setIsLogin(true)} 
              style={[styles.tab, isLogin && styles.activeTab]}
            >
              <Text style={[styles.tabText, isLogin && styles.activeTabText]}>SIGN IN</Text>
            </TouchableOpacity>
            <TouchableOpacity 
              onPress={() => setIsLogin(false)} 
              style={[styles.tab, !isLogin && styles.activeTab]}
            >
              <Text style={[styles.tabText, !isLogin && styles.activeTabText]}>REGISTER</Text>
            </TouchableOpacity>
          </View>
        )}

        {useOtp ? (
          // OTP Phone Verification Flow
          <View style={styles.formContainer}>
            <Text style={styles.formTitle}>Phone Verification</Text>
            <Text style={styles.formDesc}>We will transmit a secure dynamic passcode</Text>

            {!otpSent ? (
              <View>
                <View style={styles.inputWrapper}>
                  <Smartphone size={20} color="rgba(255,255,255,0.4)" style={styles.inputIcon} />
                  <TextInput 
                    placeholder="Phone number (+1...)" 
                    placeholderTextColor="rgba(255,255,255,0.3)"
                    style={styles.input}
                    value={phone}
                    onChangeText={setPhone}
                    keyboardType="phone-pad"
                  />
                </View>
                <TouchableOpacity onPress={handleOtpRequest} style={styles.submitBtn}>
                  {isLoading ? <ActivityIndicator color="#000" /> : <Text style={styles.submitText}>SEND PASSECODE</Text>}
                </TouchableOpacity>
              </View>
            ) : (
              <View>
                <View style={styles.inputWrapper}>
                  <Lock size={20} color="rgba(255,255,255,0.4)" style={styles.inputIcon} />
                  <TextInput 
                    placeholder="Enter 4-digit code" 
                    placeholderTextColor="rgba(255,255,255,0.3)"
                    style={styles.input}
                    value={otpCode}
                    onChangeText={setOtpCode}
                    keyboardType="number-pad"
                    maxLength={4}
                  />
                </View>
                <TouchableOpacity onPress={handleOtpVerify} style={styles.submitBtn}>
                  {isLoading ? <ActivityIndicator color="#000" /> : <Text style={styles.submitText}>VERIFY & ENTER</Text>}
                </TouchableOpacity>
              </View>
            )}

            <TouchableOpacity onPress={() => { setUseOtp(false); setOtpSent(false); }} style={styles.switchAuthType}>
              <Text style={styles.switchAuthText}>Back to Email/Password</Text>
            </TouchableOpacity>
          </View>
        ) : (
          // Email/Password Form
          <View style={styles.formContainer}>
            {!isLogin && (
              <View style={styles.inputWrapper}>
                <User size={20} color="rgba(255,255,255,0.4)" style={styles.inputIcon} />
                <TextInput 
                  placeholder="Full Name" 
                  placeholderTextColor="rgba(255,255,255,0.3)"
                  style={styles.input}
                  value={name}
                  onChangeText={setName}
                />
              </View>
            )}

            <View style={styles.inputWrapper}>
              <Mail size={20} color="rgba(255,255,255,0.4)" style={styles.inputIcon} />
              <TextInput 
                placeholder="Email Address" 
                placeholderTextColor="rgba(255,255,255,0.3)"
                style={styles.input}
                value={email}
                onChangeText={setEmail}
                autoCapitalize="none"
                keyboardType="email-address"
              />
            </View>

            <View style={styles.inputWrapper}>
              <Lock size={20} color="rgba(255,255,255,0.4)" style={styles.inputIcon} />
              <TextInput 
                placeholder="Password" 
                placeholderTextColor="rgba(255,255,255,0.3)"
                style={styles.input}
                value={password}
                onChangeText={setPassword}
                secureTextEntry={true}
                autoCapitalize="none"
              />
            </View>

            <TouchableOpacity onPress={handleAuth} style={styles.submitBtn}>
              {isLoading ? (
                <ActivityIndicator color="#000" />
              ) : (
                <View style={styles.btnContent}>
                  <Text style={styles.submitText}>{isLogin ? 'SIGN IN' : 'CREATE ACCOUNT'}</Text>
                  <ArrowRight size={18} color="#000" style={{ marginLeft: 6 }} />
                </View>
              )}
            </TouchableOpacity>

            {/* Social Logins */}
            <Text style={styles.dividerText}>OR SECURELY ACCESS WITH</Text>

            <View style={styles.socialRow}>
              <TouchableOpacity onPress={handleBiometrics} style={styles.socialBtn}>
                <Fingerprint size={20} color={COLORS.primary} style={{ marginRight: 6 }} />
                <Text style={styles.socialBtnText}>Biometrics</Text>
              </TouchableOpacity>
              
              <TouchableOpacity onPress={() => setUseOtp(true)} style={styles.socialBtn}>
                <Smartphone size={20} color="#FFF" style={{ marginRight: 6 }} />
                <Text style={styles.socialBtnText}>OTP Phone</Text>
              </TouchableOpacity>
            </View>
          </View>
        )}
      </GlassCard>

      <Text style={styles.legalText}>
        By entering Grye, you authorize multi-layer biometric processing in compliance with international compliance structures.
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
    backgroundColor: 'rgba(0, 255, 102, 0.04)',
    filter: Platform.OS === 'web' ? 'blur(100px)' : undefined,
  },
  header: {
    alignItems: 'center',
    marginBottom: 40,
  },
  title: {
    color: '#FFF',
    fontSize: 24,
    fontWeight: '900',
    letterSpacing: 4,
  },
  subtitle: {
    color: COLORS.textSecondary,
    fontSize: 13,
    marginTop: 6,
    textAlign: 'center',
  },
  authBox: {
    paddingVertical: 24,
    paddingHorizontal: 20,
  },
  tabContainer: {
    flexDirection: 'row',
    backgroundColor: 'rgba(255, 255, 255, 0.03)',
    borderRadius: 12,
    padding: 4,
    marginBottom: 24,
  },
  tab: {
    flex: 1,
    paddingVertical: 12,
    alignItems: 'center',
    borderRadius: 10,
  },
  activeTab: {
    backgroundColor: 'rgba(255, 255, 255, 0.08)',
    borderColor: 'rgba(255, 255, 255, 0.05)',
    borderWidth: 1,
  },
  tabText: {
    color: COLORS.textSecondary,
    fontSize: 12,
    fontWeight: '700',
    letterSpacing: 1.5,
  },
  activeTabText: {
    color: '#FFF',
  },
  formContainer: {
    width: '100%',
  },
  formTitle: {
    color: '#FFF',
    fontSize: 18,
    fontWeight: '800',
    textAlign: 'center',
    marginBottom: 6,
  },
  formDesc: {
    color: COLORS.textSecondary,
    fontSize: 12,
    textAlign: 'center',
    marginBottom: 20,
  },
  inputWrapper: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: 'rgba(255, 255, 255, 0.03)',
    borderColor: 'rgba(255, 255, 255, 0.06)',
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
    marginTop: 8,
    shadowColor: COLORS.primary,
    shadowOffset: { width: 0, height: 6 },
    shadowOpacity: 0.25,
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
    letterSpacing: 2,
    textAlign: 'center',
    marginVertical: 24,
  },
  socialRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
  },
  socialBtn: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'rgba(255,255,255,0.03)',
    borderColor: 'rgba(255,255,255,0.06)',
    borderWidth: 1,
    height: 48,
    borderRadius: 12,
    marginHorizontal: 5,
  },
  socialBtnText: {
    color: '#FFF',
    fontSize: 11,
    fontWeight: '700',
    letterSpacing: 0.5,
  },
  switchAuthType: {
    marginTop: 20,
    alignSelf: 'center',
  },
  switchAuthText: {
    color: COLORS.primary,
    fontSize: 12,
    fontWeight: '700',
  },
  legalText: {
    color: COLORS.textMuted,
    fontSize: 10,
    textAlign: 'center',
    lineHeight: 16,
    marginTop: 30,
  }
});
