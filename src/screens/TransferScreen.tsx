import React, { useState } from 'react';
import { View, Text, StyleSheet, ScrollView, TextInput, TouchableOpacity, ActivityIndicator, Platform } from 'react-native';
import { COLORS } from '../theme/colors';
import { useAppStore } from '../store/useAppStore';
import { GlassCard } from '../components/GlassCard';
import { ArrowRight, CheckCircle2, User, Globe, Shield, RefreshCw } from 'lucide-react';

export const TransferScreen: React.FC = () => {
  const { wallets, updateWalletBalance, addTransaction } = useAppStore();
  const [recipientName, setRecipientName] = useState('');
  const [iban, setIban] = useState('');
  const [amount, setAmount] = useState('');
  const [currency, setCurrency] = useState<'USD' | 'EUR'>('USD');
  const [status, setStatus] = useState<'input' | 'processing' | 'success'>('input');
  const [txReceipt, setTxReceipt] = useState<any>(null);

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
      alert('Please fill out the recipient name.');
      return;
    }
    if (!iban) {
      alert('Please enter a valid Account Number or IBAN.');
      return;
    }
    if (isNaN(parsedAmount) || parsedAmount <= 0) {
      alert('Please enter a valid amount.');
      return;
    }

    const currentWallet = wallets.find(w => w.currency === currency);
    if (!currentWallet || currentWallet.balance < parsedAmount) {
      alert('Insufficient funds in the selected wallet.');
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
        title: `Transfer to ${recipientName}`,
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
        <Text style={styles.loaderText}>SECURING TRANSACTION CHANNEL...</Text>
        <Text style={styles.loaderSub}>Processing instant SWIFT / SEPA transfer</Text>
      </View>
    );
  }

  if (status === 'success' && txReceipt) {
    return (
      <View style={styles.successContainer}>
        <CheckCircle2 size={72} color={COLORS.primary} style={{ marginBottom: 20 }} />
        <Text style={styles.successTitle}>TRANSFER DISPATCHED</Text>
        <Text style={styles.successSub}>Your funds are traversing the financial grid in real-time</Text>

        <GlassCard style={styles.receiptBox}>
          <Text style={styles.receiptHeader}>TRANSACTION RECEIPT</Text>
          
          <View style={styles.receiptRow}>
            <Text style={styles.receiptLabel}>Transaction ID</Text>
            <Text style={styles.receiptVal}>{txReceipt.id}</Text>
          </View>
          <View style={styles.receiptRow}>
            <Text style={styles.receiptLabel}>Recipient</Text>
            <Text style={styles.receiptVal}>{txReceipt.recipient}</Text>
          </View>
          <View style={styles.receiptRow}>
            <Text style={styles.receiptLabel}>Account / IBAN</Text>
            <Text style={styles.receiptVal}>{txReceipt.iban.slice(0, 10)}...</Text>
          </View>
          <View style={styles.receiptRow}>
            <Text style={styles.receiptLabel}>Total Amount</Text>
            <Text style={styles.receiptVal}>{txReceipt.currency} {txReceipt.amount.toFixed(2)}</Text>
          </View>
          <View style={styles.receiptRow}>
            <Text style={styles.receiptLabel}>Grye Processing Fee</Text>
            <Text style={styles.receiptVal}>{txReceipt.currency} {txReceipt.fee.toFixed(2)}</Text>
          </View>
          <View style={styles.receiptDivider} />
          <View style={styles.receiptRow}>
            <Text style={[styles.receiptLabel, { color: '#FFF', fontWeight: '800' }]}>Settled Sum</Text>
            <Text style={[styles.receiptVal, { color: COLORS.primary, fontWeight: '900' }]}>
              {txReceipt.currency} {txReceipt.netAmount.toFixed(2)}
            </Text>
          </View>
        </GlassCard>

        <TouchableOpacity onPress={resetForm} style={styles.doneBtn}>
          <Text style={styles.doneBtnText}>NEW TRANSFER</Text>
        </TouchableOpacity>
      </View>
    );
  }

  return (
    <ScrollView style={styles.container} showsVerticalScrollIndicator={false}>
      <View style={styles.header}>
        <Text style={styles.title}>SEND MONEY</Text>
        <Text style={styles.subtitle}>Wire assets instantly across global networks</Text>
      </View>

      {/* Recipient Details */}
      <GlassCard style={styles.box}>
        <Text style={styles.boxTitle}>Recipient Credentials</Text>
        
        <View style={styles.inputWrapper}>
          <User size={20} color="rgba(255,255,255,0.4)" style={styles.inputIcon} />
          <TextInput 
            placeholder="Beneficiary Name" 
            placeholderTextColor="rgba(255,255,255,0.25)"
            style={styles.input}
            value={recipientName}
            onChangeText={setRecipientName}
          />
        </View>

        <View style={styles.inputWrapper}>
          <Globe size={20} color="rgba(255,255,255,0.4)" style={styles.inputIcon} />
          <TextInput 
            placeholder="IBAN or Account Number" 
            placeholderTextColor="rgba(255,255,255,0.25)"
            style={styles.input}
            value={iban}
            onChangeText={setIban}
          />
        </View>

        {/* Quick Beneficiaries Select */}
        <Text style={styles.smallLabel}>QUICK ADD BENEFICIARY</Text>
        <View style={styles.bList}>
          {mockBeneficiaries.map((b, i) => (
            <TouchableOpacity key={i} onPress={() => handleSelectBeneficiary(b)} style={styles.bBadge}>
              <Text style={styles.bBadgeText}>{b.name}</Text>
            </TouchableOpacity>
          ))}
        </View>
      </GlassCard>

      {/* Amount and Wallet conversion */}
      <GlassCard style={[styles.box, { marginTop: 20 }]}>
        <Text style={styles.boxTitle}>Asset Volume</Text>
        
        <View style={styles.amountInputRow}>
          <TextInput 
            placeholder="0.00" 
            placeholderTextColor="rgba(255,255,255,0.25)"
            style={styles.amountInput}
            keyboardType="numeric"
            value={amount}
            onChangeText={setAmount}
          />
          
          <View style={styles.currencySelect}>
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
        <View style={styles.protectionRow}>
          <Shield size={16} color={COLORS.primary} style={{ marginRight: 8 }} />
          <Text style={styles.protectionText}>Encrypted & SECURE via SEPA / SWIFT network</Text>
        </View>

        {/* Interactive Fee calculation display */}
        {amount ? (
          <View style={styles.feeBreakdown}>
            <View style={styles.feeItem}>
              <Text style={styles.feeLabel}>Exchange Margin</Text>
              <Text style={styles.feeValText}>0.00%</Text>
            </View>
            <View style={styles.feeItem}>
              <Text style={styles.feeLabel}>Network Fee (0.5%)</Text>
              <Text style={styles.feeValText}>{currency} {(parseFloat(amount) * 0.005).toFixed(2)}</Text>
            </View>
          </View>
        ) : null}
      </GlassCard>

      {/* Action Transfer button */}
      <TouchableOpacity onPress={handleTransfer} style={styles.submitBtn}>
        <View style={styles.btnContent}>
          <Text style={styles.submitText}>EXECUTE WIRE TRANSFER</Text>
          <ArrowRight size={18} color="#000" style={{ marginLeft: 8 }} />
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
  inputIcon: {
    marginRight: 12,
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
    backgroundColor: 'rgba(0, 255, 102, 0.15)',
    borderColor: 'rgba(0, 255, 102, 0.3)',
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
  }
});
