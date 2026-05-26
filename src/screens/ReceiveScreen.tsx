import React, { useState } from 'react';
import { View, Text, StyleSheet, ScrollView, TouchableOpacity, Clipboard, Platform } from 'react-native';
import { COLORS } from '../theme/colors';
import { useAppStore } from '../store/useAppStore';
import { GlassCard } from '../components/GlassCard';
import { translations } from '../theme/translations';
import { Copy, QrCode, Globe, Check, AlertCircle } from 'lucide-react';

export const ReceiveScreen: React.FC = () => {
  const { wallets, language } = useAppStore();
  const [selectedCurrency, setSelectedCurrency] = useState<'USD' | 'EUR' | 'GBP'>('USD');
  const [copiedField, setCopiedField] = useState<string | null>(null);

  const activeWallet = wallets.find(w => w.currency === selectedCurrency) || wallets[0];

  const t = (key: string) => {
    return translations[language]?.[key] || translations['en']?.[key] || key;
  };

  const isRtl = language === 'ar';

  const handleCopy = (val: string, field: string) => {
    Clipboard.setString(val);
    setCopiedField(field);
    alert(t('RX_COPY_SUCCESS'));
    setTimeout(() => setCopiedField(null), 2000);
  };

  return (
    <ScrollView style={styles.container} showsVerticalScrollIndicator={false}>
      <View style={[styles.header, isRtl && styles.rtlAlign]}>
        <Text style={styles.title}>{t('RX_TITLE')}</Text>
        <Text style={styles.subtitle}>{t('RX_SUBTITLE')}</Text>
      </View>

      {/* Currency Switcher Tabs */}
      <View style={[styles.tabsContainer, isRtl && styles.rtlRow]}>
        {(['USD', 'EUR', 'GBP'] as const).map((cur) => (
          <TouchableOpacity
            key={cur}
            onPress={() => setSelectedCurrency(cur)}
            style={[
              styles.tab,
              selectedCurrency === cur && styles.tabActive
            ]}
          >
            <Text style={[
              styles.tabText,
              selectedCurrency === cur && styles.tabTextActive
            ]}>
              {cur} {isRtl ? 'حساب' : 'ACCOUNT'}
            </Text>
          </TouchableOpacity>
        ))}
      </View>

      {/* Accounts display card */}
      <GlassCard glowing={true} style={styles.accountBox}>
        <View style={[styles.accountHeader, isRtl && styles.rtlRow]}>
          <Globe size={24} color={COLORS.primary} />
          <Text style={[styles.accountHeaderTitle, isRtl ? { marginRight: 12, marginLeft: 0 } : { marginLeft: 12 }]}>
            {isRtl ? `حساب بنكي مؤسسي غراي بالـ ${selectedCurrency}` : `Grye ${selectedCurrency} Institutional Bank Account`}
          </Text>
        </View>

        <View style={styles.detailsList}>
          {selectedCurrency === 'USD' && (
            <>
              <View style={[styles.detailRow, isRtl && styles.rtlRow]}>
                <View style={[styles.detailMeta, isRtl && styles.rtlAlign]}>
                  <Text style={styles.detailLabel}>{t('RX_BANK_NAME')}</Text>
                  <Text style={styles.detailVal}>Grye Premium Trust LLC</Text>
                </View>
                <TouchableOpacity onPress={() => handleCopy('Grye Premium Trust LLC', 'bank')} style={styles.copyBtn}>
                  {copiedField === 'bank' ? <Check size={14} color={COLORS.primary} /> : <Copy size={14} color="#FFF" />}
                </TouchableOpacity>
              </View>

              <View style={[styles.detailRow, isRtl && styles.rtlRow]}>
                <View style={[styles.detailMeta, isRtl && styles.rtlAlign]}>
                  <Text style={styles.detailLabel}>{t('RX_SORT_CODE')}</Text>
                  <Text style={styles.detailVal}>{activeWallet.routingNumber || '021000021'}</Text>
                </View>
                <TouchableOpacity onPress={() => handleCopy(activeWallet.routingNumber || '021000021', 'routing')} style={styles.copyBtn}>
                  {copiedField === 'routing' ? <Check size={14} color={COLORS.primary} /> : <Copy size={14} color="#FFF" />}
                </TouchableOpacity>
              </View>

              <View style={[styles.detailRow, isRtl && styles.rtlRow]}>
                <View style={[styles.detailMeta, isRtl && styles.rtlAlign]}>
                  <Text style={styles.detailLabel}>{t('DB_ACC_NUMBER')}</Text>
                  <Text style={styles.detailVal}>{activeWallet.accountNumber}</Text>
                </View>
                <TouchableOpacity onPress={() => handleCopy(activeWallet.accountNumber, 'account')} style={styles.copyBtn}>
                  {copiedField === 'account' ? <Check size={14} color={COLORS.primary} /> : <Copy size={14} color="#FFF" />}
                </TouchableOpacity>
              </View>
            </>
          )}

          {selectedCurrency === 'EUR' && (
            <>
              <View style={[styles.detailRow, isRtl && styles.rtlRow]}>
                <View style={[styles.detailMeta, isRtl && styles.rtlAlign]}>
                  <Text style={styles.detailLabel}>{t('RX_BENEFICIARY')}</Text>
                  <Text style={styles.detailVal}>Alexander Moreau</Text>
                </View>
                <TouchableOpacity onPress={() => handleCopy('Alexander Moreau', 'name')} style={styles.copyBtn}>
                  {copiedField === 'name' ? <Check size={14} color={COLORS.primary} /> : <Copy size={14} color="#FFF" />}
                </TouchableOpacity>
              </View>

              <View style={[styles.detailRow, isRtl && styles.rtlRow]}>
                <View style={[styles.detailMeta, isRtl && styles.rtlAlign]}>
                  <Text style={styles.detailLabel}>IBAN</Text>
                  <Text style={styles.detailVal}>{activeWallet.iban || activeWallet.accountNumber}</Text>
                </View>
                <TouchableOpacity onPress={() => handleCopy(activeWallet.iban || activeWallet.accountNumber, 'iban')} style={styles.copyBtn}>
                  {copiedField === 'iban' ? <Check size={14} color={COLORS.primary} /> : <Copy size={14} color="#FFF" />}
                </TouchableOpacity>
              </View>

              <View style={[styles.detailRow, isRtl && styles.rtlRow]}>
                <View style={[styles.detailMeta, isRtl && styles.rtlAlign]}>
                  <Text style={styles.detailLabel}>BIC / SWIFT</Text>
                  <Text style={styles.detailVal}>{activeWallet.bic || 'DBREDEDDXXX'}</Text>
                </View>
                <TouchableOpacity onPress={() => handleCopy(activeWallet.bic || 'DBREDEDDXXX', 'bic')} style={styles.copyBtn}>
                  {copiedField === 'bic' ? <Check size={14} color={COLORS.primary} /> : <Copy size={14} color="#FFF" />}
                </TouchableOpacity>
              </View>
            </>
          )}

          {selectedCurrency === 'GBP' && (
            <>
              <View style={[styles.detailRow, isRtl && styles.rtlRow]}>
                <View style={[styles.detailMeta, isRtl && styles.rtlAlign]}>
                  <Text style={styles.detailLabel}>{t('RX_SORT_CODE')}</Text>
                  <Text style={styles.detailVal}>40-04-01</Text>
                </View>
                <TouchableOpacity onPress={() => handleCopy('40-04-01', 'sort')} style={styles.copyBtn}>
                  {copiedField === 'sort' ? <Check size={14} color={COLORS.primary} /> : <Copy size={14} color="#FFF" />}
                </TouchableOpacity>
              </View>

              <View style={[styles.detailRow, isRtl && styles.rtlRow]}>
                <View style={[styles.detailMeta, isRtl && styles.rtlAlign]}>
                  <Text style={styles.detailLabel}>{t('DB_ACC_NUMBER')}</Text>
                  <Text style={styles.detailVal}>{activeWallet.accountNumber.slice(10)}</Text>
                </View>
                <TouchableOpacity onPress={() => handleCopy(activeWallet.accountNumber.slice(10), 'account')} style={styles.copyBtn}>
                  {copiedField === 'account' ? <Check size={14} color={COLORS.primary} /> : <Copy size={14} color="#FFF" />}
                </TouchableOpacity>
              </View>

              <View style={[styles.detailRow, isRtl && styles.rtlRow]}>
                <View style={[styles.detailMeta, isRtl && styles.rtlAlign]}>
                  <Text style={styles.detailLabel}>IBAN</Text>
                  <Text style={styles.detailVal}>{activeWallet.iban || activeWallet.accountNumber}</Text>
                </View>
                <TouchableOpacity onPress={() => handleCopy(activeWallet.iban || activeWallet.accountNumber, 'iban')} style={styles.copyBtn}>
                  {copiedField === 'iban' ? <Check size={14} color={COLORS.primary} /> : <Copy size={14} color="#FFF" />}
                </TouchableOpacity>
              </View>
            </>
          )}
        </View>

        <View style={[styles.limitDisclaimer, isRtl && styles.rtlRow]}>
          <AlertCircle size={14} color={COLORS.primary} style={isRtl ? { marginLeft: 8 } : { marginRight: 8 }} />
          <Text style={styles.disclaimerText}>
            {isRtl ? 'لا توجد قيود على معالجة الحوالات البرقية الواردة للحساب.' : 'No limits on incoming institutional wire processing.'}
          </Text>
        </View>
      </GlassCard>

      {/* QR Payments section */}
      <Text style={[styles.sectionTitle, isRtl && styles.rtlText]}>{t('RX_QR_TITLE')}</Text>
      <GlassCard style={styles.qrBox}>
        <View style={styles.qrContainer}>
          <QrCode size={180} color="#FFFFFF" style={styles.qrGraphic} />
        </View>
        <Text style={[styles.qrDesc, isRtl && styles.rtlText]}>
          {t('RX_QR_DESC')}
        </Text>
      </GlassCard>

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
  tabsContainer: {
    flexDirection: 'row',
    backgroundColor: 'rgba(255, 255, 255, 0.02)',
    borderRadius: 12,
    padding: 4,
    marginBottom: 20,
  },
  tab: {
    flex: 1,
    paddingVertical: 10,
    alignItems: 'center',
    borderRadius: 10,
  },
  tabActive: {
    backgroundColor: 'rgba(255, 255, 255, 0.06)',
    borderColor: 'rgba(255, 255, 255, 0.05)',
    borderWidth: 1,
  },
  tabText: {
    color: COLORS.textSecondary,
    fontSize: 9,
    fontWeight: '800',
    letterSpacing: 1,
  },
  tabTextActive: {
    color: '#FFF',
  },
  accountBox: {
    padding: 20,
    marginBottom: 25,
  },
  accountHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 20,
  },
  accountHeaderTitle: {
    color: '#FFF',
    fontSize: 12,
    fontWeight: '800',
    letterSpacing: 0.5,
    marginLeft: 12,
  },
  detailsList: {
    width: '100%',
  },
  detailRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    backgroundColor: 'rgba(255,255,255,0.01)',
    borderColor: 'rgba(255,255,255,0.04)',
    borderWidth: 1,
    borderRadius: 12,
    padding: 14,
    marginBottom: 12,
  },
  detailMeta: {
    flex: 1,
  },
  detailLabel: {
    color: COLORS.textMuted,
    fontSize: 9,
    fontWeight: '800',
    letterSpacing: 1,
  },
  detailVal: {
    color: '#FFF',
    fontSize: 13,
    fontWeight: '700',
    marginTop: 4,
  },
  copyBtn: {
    width: 32,
    height: 32,
    borderRadius: 10,
    backgroundColor: 'rgba(255,255,255,0.04)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  limitDisclaimer: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: 10,
    backgroundColor: 'rgba(255, 255, 255, 0.04)',
    padding: 10,
    borderRadius: 8,
  },
  disclaimerText: {
    color: COLORS.secondary,
    fontSize: 10,
    fontWeight: '700',
  },
  sectionTitle: {
    color: '#FFF',
    fontSize: 15,
    fontWeight: '800',
    marginBottom: 16,
    letterSpacing: 1.5,
  },
  qrBox: {
    padding: 24,
    alignItems: 'center',
  },
  qrContainer: {
    backgroundColor: 'rgba(255, 255, 255, 0.01)',
    borderColor: 'rgba(255, 255, 255, 0.05)',
    borderWidth: 1,
    padding: 20,
    borderRadius: 20,
    marginBottom: 16,
  },
  qrGraphic: {
    opacity: 0.85,
  },
  qrDesc: {
    color: COLORS.textSecondary,
    fontSize: 11,
    textAlign: 'center',
    lineHeight: 18,
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
