import React, { useState } from 'react';
import { View, Text, StyleSheet, ScrollView, TouchableOpacity, ActivityIndicator, Platform } from 'react-native';
import { COLORS } from '../theme/colors';
import { useAppStore } from '../store/useAppStore';
import { GlassCard } from '../components/GlassCard';
import { Camera, FileText, CheckCircle2, ShieldAlert, Award, ArrowUp, RefreshCw } from 'lucide-react';

export const KYCScreen: React.FC = () => {
  const { kyc, updateKYC } = useAppStore();
  const [uploadingId, setUploadingId] = useState(false);
  const [uploadingSelfie, setUploadingSelfie] = useState(false);

  const handleUploadId = () => {
    setUploadingId(true);
    // Simulate high-speed Firebase Storage upload & OCR verification
    setTimeout(() => {
      setUploadingId(false);
      updateKYC({ idUploaded: true });
      alert('Passport / ID verified via smart OCR matrix!');
    }, 2000);
  };

  const handleUploadSelfie = () => {
    setUploadingSelfie(true);
    setTimeout(() => {
      setUploadingSelfie(false);
      updateKYC({ selfieUploaded: true });
      alert('Biometric selfie matching complete!');
    }, 2000);
  };

  const handleSubmitKYC = () => {
    if (!kyc.idUploaded || !kyc.selfieUploaded) {
      alert('Please upload both Passport/ID and Selfie documents.');
      return;
    }

    updateKYC({ status: 'pending', submittedAt: new Date().toLocaleDateString() });
    alert('Verification packet dispatched to security compliance division!');
    
    // Simulate instant compliance approval after 5 seconds to show rich verified state!
    setTimeout(() => {
      updateKYC({ status: 'verified' });
    }, 5000);
  };

  return (
    <ScrollView style={styles.container} showsVerticalScrollIndicator={false}>
      <View style={styles.header}>
        <Text style={styles.title}>IDENTITY VERIFICATION</Text>
        <Text style={styles.subtitle}>Institutional compliance and multi-layer KYC protection</Text>
      </View>

      {/* KYC Status Header Card */}
      <GlassCard glowing={kyc.status === 'verified'} style={styles.statusBox}>
        <View style={styles.statusHeaderRow}>
          {kyc.status === 'none' && (
            <>
              <ShieldAlert size={28} color={COLORS.warning} />
              <View style={styles.statusMeta}>
                <Text style={styles.statusTitle}>UNVERIFIED ACCOUNT</Text>
                <Text style={styles.statusDesc}>Upload credentials to unlock unlimited global wire capabilities.</Text>
              </View>
            </>
          )}

          {kyc.status === 'pending' && (
            <>
              <RefreshCw size={28} color={COLORS.info} style={styles.spinIcon} />
              <View style={styles.statusMeta}>
                <Text style={styles.statusTitle}>VERIFICATION IN PROGRESS</Text>
                <Text style={styles.statusDesc}>Compliance division reviewing documents. Average approval: 5s.</Text>
              </View>
            </>
          )}

          {kyc.status === 'verified' && (
            <>
              <CheckCircle2 size={28} color={COLORS.primary} />
              <View style={styles.statusMeta}>
                <Text style={styles.statusTitle}>GRYE COMPLIANCE STATUS: VERIFIED</Text>
                <Text style={styles.statusDesc}>Unlimited account access, premium virtual Visa, and infinite transfer caps active.</Text>
              </View>
            </>
          )}
        </View>
      </GlassCard>

      {kyc.status !== 'verified' && (
        <View>
          {/* Upload Grid */}
          <Text style={styles.sectionTitle}>Required Verification Credentials</Text>

          <GlassCard style={styles.uploadCard}>
            <View style={styles.uploadHeader}>
              <View style={styles.uploadIconWrapper}>
                <FileText size={22} color={COLORS.primary} />
              </View>
              <View style={{ flex: 1, marginLeft: 15 }}>
                <Text style={styles.uploadCardTitle}>Government Passport or National ID</Text>
                <Text style={styles.uploadCardDesc}>High-resolution photo of front & back page. Format: JPG, PNG.</Text>
              </View>
            </View>

            {kyc.idUploaded ? (
              <View style={styles.successUploadBadge}>
                <CheckCircle2 size={16} color={COLORS.primary} style={{ marginRight: 6 }} />
                <Text style={styles.successUploadText}>DOCUMENT UPLOADED & OCR PROCESSED</Text>
              </View>
            ) : (
              <TouchableOpacity onPress={handleUploadId} style={styles.uploadBtn}>
                {uploadingId ? (
                  <ActivityIndicator color="#000" />
                ) : (
                  <View style={styles.btnInner}>
                    <ArrowUp size={16} color="#000" style={{ marginRight: 6 }} />
                    <Text style={styles.uploadBtnText}>UPLOAD PASSPORT / ID</Text>
                  </View>
                )}
              </TouchableOpacity>
            )}
          </GlassCard>

          <GlassCard style={[styles.uploadCard, { marginTop: 15 }]}>
            <View style={styles.uploadHeader}>
              <View style={styles.uploadIconWrapper}>
                <Camera size={22} color={COLORS.primary} />
              </View>
              <View style={{ flex: 1, marginLeft: 15 }}>
                <Text style={styles.uploadCardTitle}>3D Biometric Liveliness Selfie</Text>
                <Text style={styles.uploadCardDesc}>Look directly into the camera lens with neutral face lighting.</Text>
              </View>
            </View>

            {kyc.selfieUploaded ? (
              <View style={styles.successUploadBadge}>
                <CheckCircle2 size={16} color={COLORS.primary} style={{ marginRight: 6 }} />
                <Text style={styles.successUploadText}>SELFIE PROCESSED & FACEMATCH OK</Text>
              </View>
            ) : (
              <TouchableOpacity onPress={handleUploadSelfie} style={styles.uploadBtn}>
                {uploadingSelfie ? (
                  <ActivityIndicator color="#000" />
                ) : (
                  <View style={styles.btnInner}>
                    <Camera size={16} color="#000" style={{ marginRight: 6 }} />
                    <Text style={styles.uploadBtnText}>INITIATE BIOMETRIC SELFIE</Text>
                  </View>
                )}
              </TouchableOpacity>
            )}
          </GlassCard>

          {/* Submission button */}
          <TouchableOpacity onPress={handleSubmitKYC} style={styles.submitBtn}>
            <Text style={styles.submitBtnText}>SUBMIT PACKET FOR AUDIT</Text>
          </TouchableOpacity>
        </View>
      )}

      {kyc.status === 'verified' && (
        <GlassCard style={styles.verifiedIntro}>
          <Award size={36} color={COLORS.primary} style={{ marginBottom: 15 }} />
          <Text style={styles.verifiedIntroTitle}>Welcome to Grye Wealth Club</Text>
          <Text style={styles.verifiedIntroDesc}>
            Your security compliance profile is verified at Level 3. Your limits are fully waived and you are enabled for high-fidelity SWIFT transactions.
          </Text>
        </GlassCard>
      )}

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
  statusBox: {
    padding: 20,
    marginBottom: 30,
  },
  statusHeaderRow: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  statusMeta: {
    flex: 1,
    marginLeft: 15,
  },
  statusTitle: {
    color: '#FFF',
    fontSize: 13,
    fontWeight: '900',
    letterSpacing: 1.5,
  },
  statusDesc: {
    color: COLORS.textSecondary,
    fontSize: 11,
    lineHeight: 18,
    marginTop: 4,
  },
  spinIcon: {
    opacity: 0.8,
  },
  sectionTitle: {
    color: '#FFF',
    fontSize: 15,
    fontWeight: '800',
    marginBottom: 16,
    letterSpacing: 1.5,
  },
  uploadCard: {
    padding: 20,
  },
  uploadHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 20,
  },
  uploadIconWrapper: {
    width: 48,
    height: 48,
    borderRadius: 12,
    backgroundColor: 'rgba(255,255,255,0.03)',
    borderColor: 'rgba(255,255,255,0.06)',
    borderWidth: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  uploadCardTitle: {
    color: '#FFF',
    fontSize: 13,
    fontWeight: '800',
  },
  uploadCardDesc: {
    color: COLORS.textSecondary,
    fontSize: 10,
    marginTop: 4,
    lineHeight: 14,
  },
  uploadBtn: {
    backgroundColor: COLORS.primary,
    height: 48,
    borderRadius: 12,
    justifyContent: 'center',
    alignItems: 'center',
    shadowColor: COLORS.primary,
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.15,
    shadowRadius: 8,
  },
  btnInner: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  uploadBtnText: {
    color: '#000',
    fontSize: 11,
    fontWeight: '900',
    letterSpacing: 1,
  },
  successUploadBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'rgba(0, 255, 102, 0.08)',
    borderColor: 'rgba(0, 255, 102, 0.2)',
    borderWidth: 1,
    borderRadius: 12,
    height: 48,
  },
  successUploadText: {
    color: COLORS.primary,
    fontSize: 10,
    fontWeight: '900',
    letterSpacing: 1,
  },
  submitBtn: {
    backgroundColor: '#FFF',
    height: 52,
    borderRadius: 14,
    justifyContent: 'center',
    alignItems: 'center',
    marginTop: 30,
  },
  submitBtnText: {
    color: '#000',
    fontSize: 12,
    fontWeight: '900',
    letterSpacing: 2,
  },
  verifiedIntro: {
    padding: 30,
    alignItems: 'center',
    borderColor: 'rgba(0, 255, 102, 0.2)',
  },
  verifiedIntroTitle: {
    color: '#FFF',
    fontSize: 18,
    fontWeight: '800',
    textAlign: 'center',
    marginBottom: 8,
  },
  verifiedIntroDesc: {
    color: COLORS.textSecondary,
    fontSize: 12,
    textAlign: 'center',
    lineHeight: 20,
  }
});
