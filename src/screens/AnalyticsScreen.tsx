import React from 'react';
import { View, Text, StyleSheet, ScrollView, Platform, Dimensions } from 'react-native';
import { COLORS } from '../theme/colors';
import { useAppStore } from '../store/useAppStore';
import { GlassCard } from '../components/GlassCard';
import Svg, { Path, Defs, LinearGradient, Stop, Circle } from 'react-native-svg';
import { translations } from '../theme/translations';
import { TrendingUp, ArrowDownLeft, ArrowUpRight, Award } from 'lucide-react';

const { width } = Dimensions.get('window');

export const AnalyticsScreen: React.FC = () => {
  const { transactions, language } = useAppStore();

  const t = (key: string) => {
    return translations[language]?.[key] || translations['en']?.[key] || key;
  };

  const isRtl = language === 'ar';

  // Simple statistics aggregation
  const income = transactions
    .filter(tx => tx.type === 'receive')
    .reduce((acc, curr) => acc + curr.amount, 0);

  const expense = transactions
    .filter(tx => tx.type === 'send' || tx.type === 'card_payment')
    .reduce((acc, curr) => acc + curr.amount, 0);

  // Render a custom premium SVG chart representing financial assets trend
  const renderPremiumChart = () => {
    const chartHeight = 150;
    const chartWidth = width - 40;
    
    // Smooth Bezier path curve representing financial progress
    const pathData = `M 0 ${chartHeight * 0.8} 
                      C ${chartWidth * 0.2} ${chartHeight * 0.75}, 
                        ${chartWidth * 0.4} ${chartHeight * 0.2}, 
                        ${chartWidth * 0.6} ${chartHeight * 0.4}, 
                        ${chartWidth * 0.8} ${chartHeight * 0.1}, 
                        ${chartWidth} ${chartHeight * 0.05}`;

    const fillPathData = `${pathData} L ${chartWidth} ${chartHeight} L 0 ${chartHeight} Z`;

    return (
      <View style={styles.chartContainer}>
        <Svg height={chartHeight} width={chartWidth}>
          <Defs>
            <LinearGradient id="glowGrad" x1="0" y1="0" x2="0" y2="1">
              <Stop offset="0%" stopColor="#FFFFFF" stopOpacity="0.15" />
              <Stop offset="100%" stopColor="#FFFFFF" stopOpacity="0.0" />
            </LinearGradient>
          </Defs>
          
          <Path d={fillPathData} fill="url(#glowGrad)" />
          
          <Path
            d={pathData}
            fill="none"
            stroke="#FFFFFF"
            strokeWidth="3.5"
            strokeLinecap="round"
          />

          <Circle cx={chartWidth} cy={chartHeight * 0.05} r="6" fill="#FFFFFF" />
          <Circle cx={chartWidth} cy={chartHeight * 0.05} r="12" fill="#FFFFFF" fillOpacity="0.2" />
        </Svg>
      </View>
    );
  };

  return (
    <ScrollView style={styles.container} showsVerticalScrollIndicator={false}>
      <View style={[styles.header, isRtl && styles.rtlAlign]}>
        <Text style={styles.title}>{t('AN_TITLE')}</Text>
        <Text style={styles.subtitle}>{t('AN_SUBTITLE')}</Text>
      </View>

      {/* SVG Trend Card */}
      <GlassCard glowing={true} style={styles.trendBox}>
        <View style={[styles.trendHeader, isRtl && styles.rtlRow]}>
          <View style={isRtl && styles.rtlAlign}>
            <Text style={styles.trendLabel}>{t('AN_NET_GROWTH')}</Text>
            <Text style={styles.trendVal}>+$3,248.50</Text>
          </View>
          <View style={[styles.trendBadge, isRtl && styles.rtlRow]}>
            <TrendingUp size={14} color="#FFF" style={isRtl ? { marginLeft: 4 } : { marginRight: 4 }} />
            <Text style={styles.trendBadgeText}>+18.4%</Text>
          </View>
        </View>

        {renderPremiumChart()}

        <View style={[styles.chartFooter, isRtl && styles.rtlRow]}>
          <Text style={styles.chartFootLabel}>MAY 1</Text>
          <Text style={styles.chartFootLabel}>MAY 10</Text>
          <Text style={styles.chartFootLabel}>MAY 20</Text>
          <Text style={styles.chartFootLabel}>MAY 26</Text>
        </View>
      </GlassCard>

      {/* Financial metrics boxes */}
      <View style={[styles.statsGrid, isRtl && styles.rtlRow]}>
        <GlassCard style={styles.statsCard}>
          <ArrowDownLeft size={20} color="#FFF" />
          <Text style={[styles.statsLabel, isRtl && styles.rtlText]}>{t('AN_INFLOWS')}</Text>
          <Text style={[styles.statsVal, isRtl && styles.rtlText]}>${income.toLocaleString(undefined, { minimumFractionDigits: 2 })}</Text>
        </GlassCard>

        <GlassCard style={styles.statsCard}>
          <ArrowUpRight size={20} color="#FFF" />
          <Text style={[styles.statsLabel, isRtl && styles.rtlText]}>{t('AN_OUTFLOWS')}</Text>
          <Text style={[styles.statsVal, isRtl && styles.rtlText]}>${expense.toLocaleString(undefined, { minimumFractionDigits: 2 })}</Text>
        </GlassCard>
      </View>

      {/* Spend allocations */}
      <Text style={[styles.sectionTitle, isRtl && styles.rtlText]}>{t('AN_CATEGORIES')}</Text>
      
      <GlassCard style={styles.categoryBox}>
        <View style={[styles.catRow, isRtl && styles.rtlRow]}>
          <View style={[styles.catMeta, isRtl && styles.rtlAlign]}>
            <Text style={styles.catTitle}>{isRtl ? 'مدفوعات البطاقة' : 'Card Payments'}</Text>
            <Text style={styles.catCount}>Visa *1024 • 4 {isRtl ? 'عمليات دفع' : 'purchases'}</Text>
          </View>
          <View style={[styles.catStats, isRtl && styles.rtlAlign]}>
            <Text style={styles.catAmt}>$134.99</Text>
            <Text style={styles.catPerc}>42.6%</Text>
          </View>
        </View>
        <View style={styles.progressBar}>
          <View style={[styles.progressVal, { width: '42.6%' }]} />
        </View>

        <View style={[styles.catRow, { marginTop: 20 }, isRtl && styles.rtlRow]}>
          <View style={[styles.catMeta, isRtl && styles.rtlAlign]}>
            <Text style={styles.catTitle}>{isRtl ? 'الحوالات البنكية الدولية' : 'Global Bank Wires'}</Text>
            <Text style={styles.catCount}>SEPA/SWIFT • 2 {isRtl ? 'حوالات' : 'transfers'}</Text>
          </View>
          <View style={[styles.catStats, isRtl && styles.rtlAlign]}>
            <Text style={styles.catAmt}>$150.00</Text>
            <Text style={styles.catPerc}>47.3%</Text>
          </View>
        </View>
        <View style={styles.progressBar}>
          <View style={[styles.progressVal, { width: '47.3%', backgroundColor: '#E4E4E7' }]} />
        </View>

        <View style={[styles.catRow, { marginTop: 20 }, isRtl && styles.rtlRow]}>
          <View style={[styles.catMeta, isRtl && styles.rtlAlign]}>
            <Text style={styles.catTitle}>{isRtl ? 'رسوم الشبكة والصرف' : 'Network Exchange Fees'}</Text>
            <Text style={styles.catCount}>{isRtl ? 'رسوم دفتر الحسابات غراي' : 'Grye local ledger fee'}</Text>
          </View>
          <View style={[styles.catStats, isRtl && styles.rtlAlign]}>
            <Text style={styles.catAmt}>$31.20</Text>
            <Text style={styles.catPerc}>10.1%</Text>
          </View>
        </View>
        <View style={styles.progressBar}>
          <View style={[styles.progressVal, { width: '10.1%', backgroundColor: '#71717A' }]} />
        </View>
      </GlassCard>

      {/* Premium Wealth badge */}
      <GlassCard style={[styles.wealthBadge, isRtl && styles.rtlRow]}>
        <Award size={24} color="#FFF" style={isRtl ? { marginLeft: 15 } : { marginRight: 15 }} />
        <View style={[{ flex: 1 }, isRtl && styles.rtlAlign]}>
          <Text style={styles.wealthTitle}>{t('AN_WEALTH_TITLE')}</Text>
          <Text style={[styles.wealthDesc, isRtl && styles.rtlText]}>{t('AN_WEALTH_DESC')}</Text>
        </View>
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
  trendBox: {
    padding: 20,
    marginBottom: 20,
  },
  trendHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    marginBottom: 20,
  },
  trendLabel: {
    color: COLORS.textSecondary,
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 1.5,
  },
  trendVal: {
    color: '#FFF',
    fontSize: 24,
    fontWeight: '900',
    marginTop: 4,
  },
  trendBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: 'rgba(255, 255, 255, 0.04)',
    borderColor: 'rgba(255, 255, 255, 0.08)',
    borderWidth: 1,
    borderRadius: 8,
    paddingHorizontal: 8,
    paddingVertical: 4,
  },
  trendBadgeText: {
    color: COLORS.primary,
    fontSize: 11,
    fontWeight: '900',
  },
  chartContainer: {
    alignItems: 'center',
    justifyContent: 'center',
    marginVertical: 10,
  },
  chartFooter: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginTop: 10,
    borderTopWidth: 1,
    borderTopColor: 'rgba(255,255,255,0.04)',
    paddingTop: 10,
  },
  chartFootLabel: {
    color: COLORS.textMuted,
    fontSize: 8,
    fontWeight: '700',
  },
  statsGrid: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginBottom: 24,
  },
  statsCard: {
    flex: 1,
    marginHorizontal: 4,
    padding: 16,
  },
  statsLabel: {
    color: COLORS.textMuted,
    fontSize: 8,
    fontWeight: '900',
    letterSpacing: 1.5,
    marginTop: 10,
  },
  statsVal: {
    color: '#FFF',
    fontSize: 15,
    fontWeight: '800',
    marginTop: 4,
  },
  sectionTitle: {
    color: '#FFF',
    fontSize: 15,
    fontWeight: '800',
    marginBottom: 16,
    letterSpacing: 1.5,
  },
  categoryBox: {
    padding: 20,
    marginBottom: 24,
  },
  catRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 8,
  },
  catMeta: {
    flex: 1,
  },
  catTitle: {
    color: '#FFF',
    fontSize: 13,
    fontWeight: '700',
  },
  catCount: {
    color: COLORS.textSecondary,
    fontSize: 10,
    marginTop: 2,
  },
  catStats: {
    alignItems: 'flex-end',
  },
  catAmt: {
    color: '#FFF',
    fontSize: 13,
    fontWeight: '800',
  },
  catPerc: {
    color: COLORS.primary,
    fontSize: 10,
    fontWeight: '800',
    marginTop: 2,
  },
  progressBar: {
    height: 4,
    backgroundColor: 'rgba(255,255,255,0.03)',
    borderRadius: 2,
    width: '100%',
  },
  progressVal: {
    height: '100%',
    backgroundColor: COLORS.primary,
    borderRadius: 2,
  },
  wealthBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: 16,
    borderColor: 'rgba(255, 255, 255, 0.05)',
  },
  wealthTitle: {
    color: '#FFF',
    fontSize: 13,
    fontWeight: '800',
  },
  wealthDesc: {
    color: COLORS.textSecondary,
    fontSize: 10,
    lineHeight: 16,
    marginTop: 4,
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
