import React, { useState } from 'react';
import { View, Text, StyleSheet, ScrollView, TextInput, TouchableOpacity, ActivityIndicator, Platform } from 'react-native';
import { COLORS } from '../theme/colors';
import { useAppStore } from '../store/useAppStore';
import { GlassCard } from '../components/GlassCard';
import { translations } from '../theme/translations';
import { ArrowRight, CheckCircle2, User, Globe, Shield } from 'lucide-react';

export const TransferScreen: React.FC = () => {
  const { wallets, updateWalletBalance, addTransaction, language } = useAppStore();
  const [recipientName, setRecipientName] = useState('');
  const [iban, setIban] = useState('');
  const [amount, setAmount] = useState('');
  const [currency, setCurrency] = useState<'USD' | 'EUR'>('USD');
  const [status, setStatus] = useState<'input' | 'processing' | 'success'>('input');
  const [txReceipt, setTxReceipt] = useState<any>(null);

  const t = (key: string) => {
    return translations[language]?.[key] || translations['en']?.[key] || key;
  };

  const isRtl = language === 'ar';

  const mockBeneficiaries = [
    { name: 'John Doe', email: 'john@gmail.com', iban: 'DE90370400440532013000' },
    { name: 'Emma Watson', email: 'emma@watson.co.uk', iban: 'GB44BUBA40040122938211' },
    { name: 'Satoshi Nakamoto', email: 'satoshi@bitcoin.org', iban: 'US77CHAS021000021' }
  ];

  const handleSelectBeneficiary = (b: typeof mockBeneficiaries[0]) => {
    setRecipientName(b.name);
    setIban(b.iban);
  };

  const handleTransfer = () => {
    const parsedAmount = parseFloat(amount);
    if (!recipientName) {
      alert(isRtl ? 'يرجى إدخال اسم المستلم.' : 'Please fill out the recipient name.');
      return;
    }
    if (!iban) {
      alert(isRtl ? 'يرجى إدخال رقم حساب أو آيبان صالح.' : 'Please enter a valid Account Number or IBAN.');
      return;
    }
    if (isNaN(parsedAmount) || parsedAmount <= 0) {
      alert(isRtl ? 'يرجى إدخال مبلغ صالح.' : 'Please enter a valid amount.');
      return;
    }

    const currentWallet = wallets.find(w => w.currency === currency);
    if (!currentWallet || currentWallet.balance < parsedAmount) {
      alert(isRtl ? 'الرصيد غير كافٍ في المحفظة المختارة.' : 'Insufficient funds in the selected wallet.');
      return;
    }

    setStatus('processing');

    setTimeout(() => {
      // Deduct balance
      updateWalletBalance(currency, -parsedAmount);
      
      // Save transaction
      const fee = parsedAmount * 0.005; // 0.5% fee
      const netAmount = parsedAmount - fee;
      
      const newTx = {
        type: 'send' as const,
        amount: parsedAmount,
        currency: currency,
        title: isRtl ? `حوالة إلى ${recipientName}` : `Transfer to ${recipientName}`,
        subtitle: `IBAN: ${iban.slice(0, 8)}...`,
        status: 'completed' as const
      };
      
      addTransaction(newTx);

      setTxReceipt({
        id: `TX_${Date.now().toString().slice(-6)}`,
        recipient: recipientName,
        iban: iban,
        amount: parsedAmount,
        currency: currency,
        fee: fee,
        netAmount: netAmount,
        date: new Date().toLocaleDateString()
      });

      setStatus('success');
    }, 2000);
  };

  const resetForm = () => {
    setRecipientName('');
    setIban('');
    setAmount('');
    setStatus('input');
    setTxReceipt(null);
  };

  if (status === 'processing') {
    return (
      <View style={styles.loaderContainer}>
        <ActivityIndicator size="large" color={COLORS.primary} />
        <Text style={styles.loaderText}>{t('TX_PROCESSING')}</Text>
        <Text style={styles.loaderSub}>{t('TX_PROCESSING_SUB')}</Text>
      </View>
    );
  }

  if (status === 'success' && txReceipt) {
    return (
      <View style={styles.successContainer}>
        <CheckCircle2 size={72} color={COLORS.primary} style={{ marginBottom: 20 }} />
        <Text style={styles.successTitle}>{t('TX_SUCCESS_TITLE')}</Text>
        <Text style={styles.successSub}>{t('TX_SUCCESS_SUB')}</Text>

        <GlassCard style={styles.receiptBox}>
          <Text style={styles.receiptHeader}>{t('TX_RECEIPT_HEADER')}</Text>
          
          <View style={[styles.receiptRow, isRtl && styles.rtlRow]}>
            <Text style={styles.receiptLabel}>{t('TX_RECEIPT_ID')}</Text>
            <Text style={styles.receiptVal}>{txReceipt.id}</Text>
          </View>
          <View style={[styles.receiptRow, isRtl && styles.rtlRow]}>
            <Text style={styles.receiptLabel}>{t('TX_RECIPIENT')}</Text>
            <Text style={styles.receiptVal}>{txReceipt.recipient}</Text>
          </View>
          <View style={[styles.receiptRow, isRtl && styles.rtlRow]}>
            <Text style={styles.receiptLabel}>{t('TX_ACC_IBAN')}</Text>
            <Text style={styles.receiptVal}>{txReceipt.iban.slice(0, 10)}...</Text>
          </View>
          <View style={[styles.receiptRow, isRtl && styles.rtlRow]}>
            <Text style={styles.receiptLabel}>{t('TX_TOTAL_AMOUNT')}</Text>
            <Text style={styles.receiptVal}>{txReceipt.currency} {txReceipt.amount.toFixed(2)}</Text>
          </View>
          <View style={[styles.receiptRow, isRtl && styles.rtlRow]}>
            <Text style={styles.receiptLabel}>{t('TX_FEE')}</Text>
            <Text style={styles.receiptVal}>{txReceipt.currency} {txReceipt.fee.toFixed(2)}</Text>
          </View>
          <View style={styles.receiptDivider} />
          <View style={[styles.receiptRow, isRtl && styles.rtlRow]}>
            <Text style={[styles.receiptLabel, { color: '#FFF', fontWeight: '800' }]}>{t('TX_SETTLED_SUM')}</Text>
            <Text style={[styles.receiptVal, { color: COLORS.primary, fontWeight: '900' }]}>
              {txReceipt.currency} {txReceipt.netAmount.toFixed(2)}
            </Text>
          </View>
        </GlassCard>

        <TouchableOpacity onPress={resetForm} style={styles.doneBtn}>
          <Text style={styles.doneBtnText}>{t('TX_NEW_TRANSFER')}</Text>
        </TouchableOpacity>
      </View>
    );
  }

  return (
    <ScrollView style={styles.container} showsVerticalScrollIndicator={false}>
      <View style={[styles.header, isRtl && styles.rtlAlign]}>
        <Text style={styles.title}>{t('TX_TITLE')}</Text>
        <Text style={styles.subtitle}>{t('TX_SUBTITLE')}</Text>
      </View>

      {/* Recipient Details */}
      <GlassCard style={styles.box}>
        <Text style={[styles.boxTitle, isRtl && styles.rtlText]}>{t('TX_RECIPIENT_CREDENTIALS')}</Text>
        
        <View style={[styles.inputWrapper, isRtl && styles.rtlRow]}>
          <User size={20} color="rgba(255,255,255,0.4)" style={isRtl ? { marginLeft: 12 } : { marginRight: 12 }} />
          <TextInput 
            placeholder={t('TX_BENEFICIARY_NAME')} 
            placeholderTextColor="rgba(255,255,255,0.25)"
            style={[styles.input, isRtl && styles.rtlText]}
            value={recipientName}
            onChangeText={setRecipientName}
          />
        </View>

        <View style={[styles.inputWrapper, isRtl && styles.rtlRow]}>
          <Globe size={20} color="rgba(255,255,255,0.4)" style={isRtl ? { marginLeft: 12 } : { marginRight: 12 }} />
          <TextInput 
            placeholder={t('TX_IBAN_PLACEHOLDER')} 
            placeholderTextColor="rgba(255,255,255,0.25)"
            style={[styles.input, isRtl && styles.rtlText]}
            value={iban}
            onChangeText={setIban}
          />
        </View>

        {/* Quick Beneficiaries Select */}
        <Text style={[styles.smallLabel, isRtl && styles.rtlText]}>{t('TX_QUICK_BENEFICIARIES')}</Text>
        <View style={[styles.bList, isRtl && styles.rtlRow]}>
          {mockBeneficiaries.map((b, i) => (
            <TouchableOpacity key={i} onPress={() => handleSelectBeneficiary(b)} style={styles.bBadge}>
              <Text style={styles.bBadgeText}>{b.name}</Text>
            </TouchableOpacity>
          ))}
        </View>
      </GlassCard>

      {/* Amount and Wallet conversion */}
      <GlassCard style={[styles.box, { marginTop: 20 }]}>
        <Text style={[styles.boxTitle, isRtl && styles.rtlText]}>{t('TX_VOLUME')}</Text>
        
        <View style={[styles.amountInputRow, isRtl && styles.rtlRow]}>
          <TextInput 
            placeholder="0.00" 
            placeholderTextColor="rgba(255,255,255,0.25)"
            style={[styles.amountInput, isRtl && styles.rtlText]}
            keyboardType="numeric"
            value={amount}
            onChangeText={setAmount}
          />
          
          <View style={[styles.currencySelect, isRtl && styles.rtlRow]}>
            <TouchableOpacity 
              style={[styles.currencyBtn, currency === 'USD' && styles.currencyBtnActive]}
              onPress={() => setCurrency('USD')}
            >
              <Text style={styles.currencyBtnText}>USD</Text>
            </TouchableOpacity>
            <TouchableOpacity 
              style={[styles.currencyBtn, currency === 'EUR' && styles.currencyBtnActive]}
              onPress={() => setCurrency('EUR')}
            >
              <Text style={styles.currencyBtnText}>EUR</Text>
            </TouchableOpacity>
          </View>
        </View>

        {/* Transaction protection detail */}
        <View style={[styles.protectionRow, isRtl && styles.rtlRow]}>
          <Shield size={16} color={COLORS.primary} style={isRtl ? { marginLeft: 8 } : { marginRight: 8 }} />
          <Text style={styles.protectionText}>{t('TX_PROTECTION')}</Text>
        </View>

        {/* Interactive Fee calculation display */}
        {amount ? (
          <View style={styles.feeBreakdown}>
            <View style={[styles.feeItem, isRtl && styles.rtlRow]}>
              <Text style={styles.feeLabel}>{t('TX_EXCHANGE_MARGIN')}</Text>
              <Text style={styles.feeValText}>0.00%</Text>
            </View>
            <View style={[styles.feeItem, isRtl && styles.rtlRow]}>
              <Text style={styles.feeLabel}>{t('TX_NETWORK_FEE')}</Text>
              <Text style={styles.feeValText}>{currency} {(parseFloat(amount) * 0.005).toFixed(2)}</Text>
            </View>
          </View>
        ) : null}
      </GlassCard>

      {/* Action Transfer button */}
      <TouchableOpacity onPress={handleTransfer} style={styles.submitBtn}>
        <View style={[styles.btnContent, isRtl && styles.rtlRow]}>
          <Text style={styles.submitText}>{t('TX_EXECUTE')}</Text>
          <ArrowRight size={18} color="#000" style={isRtl ? { marginRight: 8 } : { marginLeft: 8 }} />
        </View>
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
  box: {
    padding: 20,
  },
  boxTitle: {
    color: '#FFF',
    fontSize: 14,
    fontWeight: '800',
    marginBottom: 16,
    letterSpacing: 1,
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
  input: {
    flex: 1,
    color: '#FFF',
    fontSize: 14,
    height: '100%',
  },
  smallLabel: {
    color: COLORS.textMuted,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 1.5,
    marginTop: 10,
    marginBottom: 10,
  },
  bList: {
    flexDirection: 'row',
  },
  bBadge: {
    backgroundColor: 'rgba(255,255,255,0.03)',
    borderColor: 'rgba(255,255,255,0.05)',
    borderWidth: 1,
    borderRadius: 10,
    paddingHorizontal: 12,
    paddingVertical: 8,
    marginRight: 8,
  },
  bBadgeText: {
    color: '#FFF',
    fontSize: 11,
    fontWeight: '700',
  },
  amountInputRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(255,255,255,0.08)',
    paddingBottom: 10,
    marginBottom: 20,
  },
  amountInput: {
    color: '#FFF',
    fontSize: 32,
    fontWeight: '900',
    flex: 1,
    outlineStyle: Platform.OS === 'web' ? 'none' : undefined,
  } as any,
  currencySelect: {
    flexDirection: 'row',
  },
  currencyBtn: {
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 8,
    backgroundColor: 'rgba(255,255,255,0.02)',
    marginLeft: 6,
  },
  currencyBtnActive: {
    backgroundColor: 'rgba(255, 255, 255, 0.08)',
    borderColor: 'rgba(255, 255, 255, 0.15)',
    borderWidth: 1,
  },
  currencyBtnText: {
    color: '#FFF',
    fontSize: 11,
    fontWeight: '800',
  },
  protectionRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: 10,
  },
  protectionText: {
    color: COLORS.textSecondary,
    fontSize: 11,
  },
  feeBreakdown: {
    marginTop: 20,
    borderTopWidth: 1,
    borderTopColor: 'rgba(255,255,255,0.05)',
    paddingTop: 15,
  },
  feeItem: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginBottom: 8,
  },
  feeLabel: {
    color: COLORS.textMuted,
    fontSize: 11,
  },
  feeValText: {
    color: '#FFF',
    fontSize: 11,
    fontWeight: '700',
  },
  submitBtn: {
    backgroundColor: COLORS.primary,
    height: 54,
    borderRadius: 16,
    justifyContent: 'center',
    alignItems: 'center',
    marginTop: 30,
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
  loaderContainer: {
    flex: 1,
    backgroundColor: COLORS.background,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 20,
  },
  loaderText: {
    color: '#FFF',
    fontSize: 14,
    fontWeight: '900',
    letterSpacing: 3,
    marginTop: 24,
  },
  loaderSub: {
    color: COLORS.textSecondary,
    fontSize: 11,
    marginTop: 6,
  },
  successContainer: {
    flex: 1,
    backgroundColor: COLORS.background,
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: 20,
  },
  successTitle: {
    color: COLORS.primary,
    fontSize: 22,
    fontWeight: '900',
    letterSpacing: 3,
    textAlign: 'center',
  },
  successSub: {
    color: COLORS.textSecondary,
    fontSize: 12,
    textAlign: 'center',
    marginTop: 6,
    marginBottom: 30,
  },
  receiptBox: {
    width: '100%',
    maxWidth: 360,
    padding: 24,
    marginBottom: 30,
  },
  receiptHeader: {
    color: '#FFF',
    fontSize: 12,
    fontWeight: '900',
    letterSpacing: 2,
    textAlign: 'center',
    marginBottom: 20,
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(255,255,255,0.06)',
    paddingBottom: 10,
  },
  receiptRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginVertical: 8,
  },
  receiptLabel: {
    color: COLORS.textSecondary,
    fontSize: 12,
  },
  receiptVal: {
    color: '#FFF',
    fontSize: 12,
    fontWeight: '700',
  },
  receiptDivider: {
    height: 1,
    backgroundColor: 'rgba(255,255,255,0.08)',
    marginVertical: 12,
  },
  doneBtn: {
    backgroundColor: '#FFF',
    height: 52,
    borderRadius: 14,
    paddingHorizontal: 30,
    justifyContent: 'center',
    alignItems: 'center',
  },
  doneBtnText: {
    color: '#000',
    fontSize: 12,
    fontWeight: '900',
    letterSpacing: 2,
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
