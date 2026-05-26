import React, { useState } from 'react';
import { View, Text, StyleSheet, ScrollView, TouchableOpacity, TextInput, ActivityIndicator, Platform } from 'react-native';
import { COLORS } from '../theme/colors';
import { useAppStore } from '../store/useAppStore';
import { TransactionList } from '../components/TransactionList';
import { ArrowUpRight, ArrowDownLeft, CreditCard, BarChart3, RefreshCw, Copy } from 'lucide-react';
import { GlassCard } from '../components/GlassCard';
import { translations } from '../theme/translations';

interface DashboardScreenProps {
  onNavigate: (screen: string) => void;
}

export const DashboardScreen: React.FC<DashboardScreenProps> = ({ onNavigate }) => {
  const { wallets, transactions, updateWalletBalance, addTransaction, language, user } = useAppStore();
  const [exchangeFrom, setExchangeFrom] = useState<'USD' | 'EUR'>('USD');
  const [exchangeTo, setExchangeTo] = useState<'USD' | 'EUR' | 'GBP'>('EUR');
  const [exchangeAmount, setExchangeAmount] = useState('');
  const [isExchanging, setIsExchanging] = useState(false);

  const t = (key: string) => {
    return translations[language]?.[key] || translations['en']?.[key] || key;
  };

  const isRtl = language === 'ar';

  // Exchange rate definitions
  const rates = {
    USD_EUR: 0.92,
    USD_GBP: 0.79,
    EUR_USD: 1.09,
    EUR_GBP: 0.86,
  };

  const getExchangeRate = () => {
    if (exchangeFrom === 'USD' && exchangeTo === 'EUR') return rates.USD_EUR;
    if (exchangeFrom === 'USD' && exchangeTo === 'GBP') return rates.USD_GBP;
    if (exchangeFrom === 'EUR' && exchangeTo === 'USD') return rates.EUR_USD;
    if (exchangeFrom === 'EUR' && exchangeTo === 'GBP') return rates.EUR_GBP;
    return 1;
  };

  // Aggregated total balance in USD
  const totalBalanceUSD = wallets.reduce((acc, curr) => {
    if (curr.currency === 'USD') return acc + curr.balance;
    if (curr.currency === 'EUR') return acc + curr.balance * rates.EUR_USD;
    if (curr.currency === 'GBP') return acc + curr.balance * rates.USD_GBP;
    return acc;
  }, 0);

  const handleExchange = () => {
    const amount = parseFloat(exchangeAmount);
    if (isNaN(amount) || amount <= 0) {
      alert(isRtl ? 'يرجى إدخال مبلغ صالح.' : 'Please enter a valid amount.');
      return;
    }

    const sourceWallet = wallets.find(w => w.currency === exchangeFrom);
    if (!sourceWallet || sourceWallet.balance < amount) {
      alert(isRtl ? 'الرصيد غير كافٍ لإتمام عملية التحويل.' : 'Insufficient wallet funds.');
      return;
    }

    setIsExchanging(true);

    setTimeout(() => {
      const rate = getExchangeRate();
      const targetAmount = amount * rate;
      
      // Perform balances mutations
      updateWalletBalance(exchangeFrom, -amount);
      updateWalletBalance(exchangeTo, targetAmount);

      // Save transaction ledger entry
      addTransaction({
        type: 'exchange',
        amount: targetAmount,
        currency: exchangeTo,
        title: isRtl ? `صرف ${exchangeFrom} إلى ${exchangeTo}` : `Exchanged ${exchangeFrom} to ${exchangeTo}`,
        subtitle: isRtl ? `المعدل: 1 ${exchangeFrom} = ${rate} ${exchangeTo}` : `Rate: 1 ${exchangeFrom} = ${rate} ${exchangeTo}`,
        status: 'completed'
      });

      setIsExchanging(false);
      setExchangeAmount('');
      alert(isRtl ? 'تمت عملية تحويل العملة بنجاح!' : 'Exchange completed successfully!');
    }, 1500);
  };

  const handleCopy = (text: string) => {
    alert(isRtl ? 'تم نسخ الحساب إلى الحافظة!' : 'Account copied to clipboard!');
  };

  const formattedName = user?.fullName ? user.fullName.split(' ')[0].toUpperCase() : 'ALEXANDER';

  return (
    <ScrollView style={styles.container} showsVerticalScrollIndicator={false}>
      {/* Header Profile / Status */}
      <View style={[styles.header, isRtl && styles.rtlRow]}>
        <View style={isRtl && styles.rtlAlign}>
          <Text style={styles.greetingText}>
            {isRtl ? `مرحباً، ${formattedName}` : `HELLO, ${formattedName}`}
          </Text>
          <View style={styles.premiumBadge}>
            <Text style={styles.premiumText}>{t('DB_PREMIUM_BADGE')}</Text>
          </View>
        </View>
        <TouchableOpacity onPress={() => onNavigate('settings')} style={styles.profileAvatar}>
          <Text style={styles.avatarText}>{formattedName.slice(0, 2)}</Text>
        </TouchableOpacity>
      </View>

      {/* Aggregate balance card */}
      <View style={styles.balanceSection}>
        <Text style={styles.balanceLabel}>{t('DB_COMBINED_BALANCE')}</Text>
        <Text style={styles.balanceVal}>${totalBalanceUSD.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</Text>
        <Text style={styles.subText}>{t('DB_SYNC_STATUS')}</Text>
      </View>

      {/* Quick Action Navigation Grid */}
      <View style={[styles.actionGrid, isRtl && styles.rtlRow]}>
        <TouchableOpacity activeOpacity={0.7} onPress={() => onNavigate('transfer')} style={styles.actionBtn}>
          <View style={[styles.actionIconContainer, { backgroundColor: 'rgba(255, 255, 255, 0.04)' }]}>
            <ArrowUpRight size={22} color="#FFF" />
          </View>
          <Text style={styles.actionLabel}>{t('NAV_SEND')}</Text>
        </TouchableOpacity>

        <TouchableOpacity activeOpacity={0.7} onPress={() => onNavigate('receive')} style={styles.actionBtn}>
          <View style={[styles.actionIconContainer, { backgroundColor: 'rgba(255, 255, 255, 0.04)' }]}>
            <ArrowDownLeft size={22} color="#FFF" />
          </View>
          <Text style={styles.actionLabel}>{t('NAV_RECEIVE')}</Text>
        </TouchableOpacity>

        <TouchableOpacity activeOpacity={0.7} onPress={() => onNavigate('cards')} style={styles.actionBtn}>
          <View style={[styles.actionIconContainer, { backgroundColor: 'rgba(255, 255, 255, 0.04)' }]}>
            <CreditCard size={22} color="#FFF" />
          </View>
          <Text style={styles.actionLabel}>{t('NAV_CARDS')}</Text>
        </TouchableOpacity>

        <TouchableOpacity activeOpacity={0.7} onPress={() => onNavigate('analytics')} style={styles.actionBtn}>
          <View style={[styles.actionIconContainer, { backgroundColor: 'rgba(255, 255, 255, 0.04)' }]}>
            <BarChart3 size={22} color="#FFF" />
          </View>
          <Text style={styles.actionLabel}>{t('NAV_REPORTS')}</Text>
        </TouchableOpacity>
      </View>

      {/* Multi-Currency Wallets Carousel / Grid */}
      <Text style={[styles.sectionTitle, isRtl && styles.rtlText]}>{t('DB_GLOBAL_ACCOUNTS')}</Text>
      <ScrollView horizontal={true} showsHorizontalScrollIndicator={false} style={styles.walletsScroll}>
        <View style={[styles.walletsRow, isRtl && styles.rtlRow]}>
          {wallets.map((wallet) => (
            <GlassCard key={wallet.id} style={styles.walletCard}>
              <View style={[styles.walletHeader, isRtl && styles.rtlRow]}>
                <Text style={styles.walletCurrency}>{wallet.currency}</Text>
                <Text style={styles.walletSymbol}>
                  {wallet.currency === 'USD' ? '$' : wallet.currency === 'EUR' ? '€' : '£'}
                </Text>
              </View>
              <Text style={[styles.walletBalance, isRtl && styles.rtlText]}>
                {wallet.currency === 'USD' ? '$' : wallet.currency === 'EUR' ? '€' : '£'}
                {wallet.balance.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
              </Text>
              <View style={[styles.walletFooter, isRtl && styles.rtlRow]}>
                <View style={isRtl && styles.rtlAlign}>
                  <Text style={styles.accNumLabel}>{t('DB_ACC_NUMBER')}</Text>
                  <Text style={styles.accNumVal}>{wallet.accountNumber.slice(0, 16)}...</Text>
                </View>
                <TouchableOpacity onPress={() => handleCopy(wallet.accountNumber)} style={styles.copyBtn}>
                  <Copy size={12} color="#FFF" />
                </TouchableOpacity>
              </View>
            </GlassCard>
          ))}
        </View>
      </ScrollView>

      {/* Currency Exchange Widget */}
      <Text style={[styles.sectionTitle, isRtl && styles.rtlText]}>{t('DB_CONVERTER')}</Text>
      <GlassCard style={styles.exchangeWidget}>
        <View style={[styles.converterRow, isRtl && styles.rtlRow]}>
          <View style={styles.convertHalf}>
            <Text style={[styles.convertLabel, isRtl && styles.rtlText]}>{t('DB_CONVERT_FROM')}</Text>
            <TextInput 
              placeholder="0.00" 
              placeholderTextColor="rgba(255,255,255,0.2)"
              style={[styles.convertInput, isRtl && styles.rtlText]}
              keyboardType="numeric"
              value={exchangeAmount}
              onChangeText={setExchangeAmount}
            />
            <View style={[styles.currencySelect, isRtl && styles.rtlRow]}>
              <TouchableOpacity 
                style={[styles.currencyBtn, exchangeFrom === 'USD' && styles.currencyBtnActive]}
                onPress={() => { setExchangeFrom('USD'); setExchangeTo('EUR'); }}
              >
                <Text style={styles.currencyBtnText}>USD</Text>
              </TouchableOpacity>
              <TouchableOpacity 
                style={[styles.currencyBtn, exchangeFrom === 'EUR' && styles.currencyBtnActive]}
                onPress={() => { setExchangeFrom('EUR'); setExchangeTo('USD'); }}
              >
                <Text style={styles.currencyBtnText}>EUR</Text>
              </TouchableOpacity>
            </View>
          </View>

          <View style={[styles.exchangeIconMiddle, isRtl ? { transform: [{ rotate: '180deg' }] } : undefined]}>
            <RefreshCw size={20} color={COLORS.primary} />
          </View>

          <View style={styles.convertHalf}>
            <Text style={[styles.convertLabel, isRtl && styles.rtlText]}>{t('DB_CONVERT_TO')}</Text>
            <Text style={[styles.convertedAmount, isRtl && styles.rtlText]}>
              {exchangeAmount ? (parseFloat(exchangeAmount) * getExchangeRate()).toFixed(2) : '0.00'}
            </Text>
            <View style={[styles.currencySelect, isRtl && styles.rtlRow]}>
              <TouchableOpacity 
                style={[styles.currencyBtn, exchangeTo === 'EUR' && styles.currencyBtnActive]}
                onPress={() => setExchangeTo('EUR')}
                disabled={exchangeFrom === 'EUR'}
              >
                <Text style={styles.currencyBtnText}>EUR</Text>
              </TouchableOpacity>
              <TouchableOpacity 
                style={[styles.currencyBtn, exchangeTo === 'GBP' && styles.currencyBtnActive]}
                onPress={() => setExchangeTo('GBP')}
              >
                <Text style={styles.currencyBtnText}>GBP</Text>
              </TouchableOpacity>
              <TouchableOpacity 
                style={[styles.currencyBtn, exchangeTo === 'USD' && styles.currencyBtnActive]}
                onPress={() => setExchangeTo('USD')}
                disabled={exchangeFrom === 'USD'}
              >
                <Text style={styles.currencyBtnText}>USD</Text>
              </TouchableOpacity>
            </View>
          </View>
        </View>

        <TouchableOpacity onPress={handleExchange} style={styles.exchangeSubmitBtn}>
          {isExchanging ? (
            <ActivityIndicator color="#000" />
          ) : (
            <Text style={styles.exchangeSubmitText}>{t('DB_CONVERT_BTN')}</Text>
          )}
        </TouchableOpacity>
      </GlassCard>

      {/* Recent Ledger Feed */}
      <View style={[styles.sectionHeaderRow, isRtl && styles.rtlRow]}>
        <Text style={styles.sectionTitle}>{t('DB_TRANSACTIONS')}</Text>
        <TouchableOpacity onPress={() => onNavigate('analytics')}>
          <Text style={styles.viewAllText}>{t('DB_VIEW_ALL')}</Text>
        </TouchableOpacity>
      </View>
      <TransactionList transactions={transactions} limit={4} />

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
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 30,
    marginTop: Platform.OS === 'ios' ? 40 : 10,
  },
  greetingText: {
    color: '#FFF',
    fontSize: 18,
    fontWeight: '900',
    letterSpacing: 2,
  },
  premiumBadge: {
    backgroundColor: 'rgba(255, 255, 255, 0.04)',
    borderColor: 'rgba(255, 255, 255, 0.08)',
    borderWidth: 1,
    borderRadius: 8,
    paddingHorizontal: 8,
    paddingVertical: 3,
    marginTop: 4,
    alignSelf: 'flex-start',
  },
  premiumText: {
    color: COLORS.primary,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 1.5,
  },
  profileAvatar: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: 'rgba(255,255,255,0.06)',
    borderColor: 'rgba(255,255,255,0.1)',
    borderWidth: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  avatarText: {
    color: '#FFF',
    fontSize: 14,
    fontWeight: '800',
  },
  balanceSection: {
    alignItems: 'center',
    marginBottom: 35,
  },
  balanceLabel: {
    color: COLORS.textSecondary,
    fontSize: 10,
    fontWeight: '900',
    letterSpacing: 2,
    marginBottom: 8,
  },
  balanceVal: {
    color: '#FFF',
    fontSize: 38,
    fontWeight: '900',
    letterSpacing: 1,
  },
  subText: {
    color: COLORS.textMuted,
    fontSize: 11,
    marginTop: 4,
  },
  actionGrid: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginBottom: 35,
  },
  actionBtn: {
    flex: 1,
    alignItems: 'center',
  },
  actionIconContainer: {
    width: 56,
    height: 56,
    borderRadius: 18,
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 8,
  },
  actionLabel: {
    color: '#FFF',
    fontSize: 12,
    fontWeight: '700',
  },
  sectionTitle: {
    color: '#FFF',
    fontSize: 16,
    fontWeight: '800',
    marginBottom: 16,
    letterSpacing: 1.5,
  },
  sectionHeaderRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginTop: 15,
  },
  viewAllText: {
    color: COLORS.primary,
    fontSize: 12,
    fontWeight: '700',
  },
  walletsScroll: {
    flexDirection: 'row',
    marginBottom: 30,
  },
  walletsRow: {
    flexDirection: 'row',
  },
  walletCard: {
    width: 260,
    marginRight: 16,
    padding: 20,
    height: 150,
    justifyContent: 'space-between',
  },
  walletHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  walletCurrency: {
    color: COLORS.textSecondary,
    fontSize: 12,
    fontWeight: '800',
    letterSpacing: 1,
  },
  walletSymbol: {
    color: COLORS.primary,
    fontSize: 18,
    fontWeight: '900',
  },
  walletBalance: {
    color: '#FFF',
    fontSize: 24,
    fontWeight: '800',
    letterSpacing: 0.5,
  },
  walletFooter: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  accNumLabel: {
    color: COLORS.textMuted,
    fontSize: 8,
    fontWeight: '700',
    letterSpacing: 0.5,
  },
  accNumVal: {
    color: COLORS.textSecondary,
    fontSize: 11,
    fontWeight: '600',
  },
  copyBtn: {
    width: 24,
    height: 24,
    borderRadius: 8,
    backgroundColor: 'rgba(255, 255, 255, 0.05)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  exchangeWidget: {
    padding: 20,
    marginBottom: 35,
  },
  converterRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  convertHalf: {
    flex: 1.2,
  },
  convertLabel: {
    color: COLORS.textMuted,
    fontSize: 9,
    fontWeight: '800',
    letterSpacing: 1,
    marginBottom: 6,
  },
  convertInput: {
    color: '#FFF',
    fontSize: 22,
    fontWeight: '800',
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(255,255,255,0.08)',
    paddingBottom: 4,
    marginBottom: 10,
    outlineStyle: Platform.OS === 'web' ? 'none' : undefined,
  } as any,
  convertedAmount: {
    color: COLORS.primary,
    fontSize: 22,
    fontWeight: '800',
    paddingBottom: 4,
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(255,255,255,0.08)',
    marginBottom: 10,
  },
  exchangeIconMiddle: {
    flex: 0.4,
    alignItems: 'center',
    justifyContent: 'center',
  },
  currencySelect: {
    flexDirection: 'row',
  },
  currencyBtn: {
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 6,
    backgroundColor: 'rgba(255,255,255,0.02)',
    marginRight: 4,
    borderColor: 'rgba(255,255,255,0.04)',
    borderWidth: 1,
  },
  currencyBtnActive: {
    backgroundColor: 'rgba(255, 255, 255, 0.08)',
    borderColor: 'rgba(255, 255, 255, 0.15)',
  },
  currencyBtnText: {
    color: '#FFF',
    fontSize: 9,
    fontWeight: '800',
  },
  exchangeSubmitBtn: {
    backgroundColor: COLORS.primary,
    height: 46,
    borderRadius: 12,
    justifyContent: 'center',
    alignItems: 'center',
    marginTop: 20,
    shadowColor: COLORS.primary,
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.2,
    shadowRadius: 8,
  },
  exchangeSubmitText: {
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
