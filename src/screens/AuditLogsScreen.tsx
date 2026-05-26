import React, { useState } from 'react';
import { View, Text, StyleSheet, ScrollView, TouchableOpacity, TextInput, Platform } from 'react-native';
import { COLORS } from '../theme/colors';
import { useAppStore, AuditLog } from '../store/useAppStore';
import { GlassCard } from '../components/GlassCard';
import { translations } from '../theme/translations';
import { Search, Shield, Database, CreditCard, UserCheck, Settings, Play, Trash2 } from 'lucide-react';

export const AuditLogsScreen: React.FC = () => {
  const { logs, language, addLog, resetAll } = useAppStore();
  const [selectedCategory, setSelectedCategory] = useState<string>('all');
  const [searchQuery, setSearchQuery] = useState('');

  const t = (key: string) => {
    return translations[language]?.[key] || translations['en']?.[key] || key;
  };

  const isRtl = language === 'ar';

  const categories = [
    { code: 'all', label: t('LOGS_CATEGORY_ALL') },
    { code: 'auth', label: t('LOGS_CATEGORY_AUTH'), icon: Shield, color: COLORS.warning },
    { code: 'transaction', label: t('LOGS_CATEGORY_TX'), icon: Database, color: COLORS.primary },
    { code: 'card', label: t('LOGS_CATEGORY_CARD'), icon: CreditCard, color: COLORS.info },
    { code: 'kyc', label: t('LOGS_CATEGORY_KYC'), icon: UserCheck, color: '#F59E0B' },
    { code: 'system', label: t('LOGS_CATEGORY_SYSTEM'), icon: Settings, color: '#A855F7' }
  ];

  // Helper to render beautiful visual representation of the log type
  const getLogIcon = (category: AuditLog['category']) => {
    switch (category) {
      case 'auth':
        return <Shield size={16} color={COLORS.warning} />;
      case 'transaction':
        return <Database size={16} color={COLORS.primary} />;
      case 'card':
        return <CreditCard size={16} color={COLORS.info} />;
      case 'kyc':
        return <UserCheck size={16} color="#F59E0B" />;
      case 'system':
        return <Settings size={16} color="#A855F7" />;
      default:
        return <Settings size={16} color="#FFF" />;
    }
  };

  // Filter logs based on search query and category
  const filteredLogs = logs.filter(log => {
    const matchesCategory = selectedCategory === 'all' || log.category === selectedCategory;
    const matchesSearch = searchQuery === '' || 
      log.action.toLowerCase().includes(searchQuery.toLowerCase()) || 
      log.description.toLowerCase().includes(searchQuery.toLowerCase());
    return matchesCategory && matchesSearch;
  });

  const handleSimulateLog = () => {
    const simulatedEvents = [
      { action: 'SECURE_TUNNEL_REFRESHED', category: 'system' as const, desc: 'TLS 1.3 cryptographic secure network tunnel handshake refreshed.' },
      { action: 'STRIPE_GATEWAY_PING', category: 'transaction' as const, desc: 'Stripe gateway API channels pinged. Gateway operational latency: 45ms.' },
      { action: 'COMPLIANCE_CHECKSUM_OK', category: 'kyc' as const, desc: 'Biometric liveliness anti-spoof integrity checksum validated successfully.' },
      { action: 'BIOMETRICS_SUCCESS', category: 'auth' as const, desc: 'Local Face ID credentials successfully matched cryptographic profile signature.' }
    ];

    const randomEvent = simulatedEvents[Math.floor(Math.random() * simulatedEvents.length)];
    addLog(randomEvent.action, randomEvent.category, randomEvent.desc);
  };

  const handleClearLogs = () => {
    resetAll();
    alert(isRtl ? 'تم تطهير سجلات النظام والحافظة الأمنية.' : 'System operation ledger and cache purged successfully.');
  };

  return (
    <View style={styles.outerContainer}>
      <ScrollView style={styles.container} showsVerticalScrollIndicator={false}>
        {/* Header section */}
        <View style={[styles.header, isRtl && styles.rtlRow]}>
          <View style={[styles.headerTexts, isRtl && styles.rtlAlign]}>
            <Text style={styles.title}>{t('LOGS_TITLE')}</Text>
            <Text style={styles.subtitle}>{t('LOGS_SUBTITLE')}</Text>
          </View>
        </View>

        {/* Dynamic Simulation Controls Card */}
        <GlassCard style={styles.simCard}>
          <Text style={[styles.simTitle, isRtl && styles.rtlText]}>
            {isRtl ? 'محاكي أمن المعالجة الفنية' : 'System Processing Simulation Console'}
          </Text>
          <Text style={[styles.simDesc, isRtl && styles.rtlText]}>
            {isRtl ? 'قم بتشغيل أحداث معالجة أمنية لمحاكاة استجابات البنية التحتية الخلفية.' : 'Trigger state-changing security logs to simulate institutional database handshakes.'}
          </Text>
          <View style={[styles.simActionsRow, isRtl && styles.rtlRow]}>
            <TouchableOpacity onPress={handleSimulateLog} style={styles.simBtn}>
              <Play size={14} color="#000" style={{ marginRight: 6 }} />
              <Text style={styles.simBtnText}>{isRtl ? 'محاكاة حدث فني' : 'SIMULATE EVENT'}</Text>
            </TouchableOpacity>

            <TouchableOpacity onPress={handleClearLogs} style={styles.clearBtn}>
              <Trash2 size={14} color="#EF4444" style={{ marginRight: 6 }} />
              <Text style={styles.clearBtnText}>{isRtl ? 'تطهير السجل' : 'PURGE CACHE'}</Text>
            </TouchableOpacity>
          </View>
        </GlassCard>

        {/* Dynamic Search Bar */}
        <View style={[styles.searchWrapper, isRtl && styles.rtlRow]}>
          <Search size={18} color="rgba(255,255,255,0.4)" style={styles.searchIcon} />
          <TextInput 
            placeholder={isRtl ? 'ابحث في السجلات (أمان، تحويل...)' : 'Search audit database (security, status...)'}
            placeholderTextColor="rgba(255,255,255,0.3)"
            style={[styles.searchInput, isRtl && styles.rtlText]}
            value={searchQuery}
            onChangeText={setSearchQuery}
          />
        </View>

        {/* Horizontal Category selector */}
        <ScrollView horizontal={true} showsHorizontalScrollIndicator={false} style={styles.catScroll}>
          <View style={[styles.catRow, isRtl && styles.rtlRow]}>
            {categories.map((cat) => (
              <TouchableOpacity
                key={cat.code}
                onPress={() => setSelectedCategory(cat.code)}
                style={[
                  styles.catBadge,
                  selectedCategory === cat.code && styles.catBadgeActive,
                  selectedCategory === cat.code && { borderColor: cat.color + '40', backgroundColor: cat.color + '0C' }
                ]}
              >
                <Text style={[
                  styles.catLabel,
                  selectedCategory === cat.code && styles.catLabelActive,
                  selectedCategory === cat.code && { color: cat.color }
                ]}>
                  {cat.label}
                </Text>
              </TouchableOpacity>
            ))}
          </View>
        </ScrollView>

        {/* Auditing timeline logs list */}
        {filteredLogs.length === 0 ? (
          <View style={styles.emptyContainer}>
            <Text style={styles.emptyText}>{t('LOGS_EMPTY')}</Text>
          </View>
        ) : (
          <View style={styles.timelineList}>
            {filteredLogs.map((log) => {
              const logDate = new Date(log.timestamp);
              const formattedTime = logDate.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit', second: '2-digit' });
              
              return (
                <GlassCard key={log.id} style={styles.logCard}>
                  <View style={[styles.logHeaderRow, isRtl && styles.rtlRow]}>
                    <View style={[styles.logMetaLeft, isRtl && styles.rtlRow]}>
                      <View style={[styles.logIconBox, { backgroundColor: 'rgba(255,255,255,0.02)', borderColor: 'rgba(255,255,255,0.05)' }]}>
                        {getLogIcon(log.category)}
                      </View>
                      <View style={[styles.titleGroup, isRtl && { marginRight: 12, marginLeft: 0 }]}>
                        <Text style={styles.logAction}>{log.action}</Text>
                        <Text style={styles.logTimestamp}>{formattedTime}</Text>
                      </View>
                    </View>
                    <View style={styles.categoryBadge}>
                      <Text style={[styles.categoryText, { color: categories.find(c => c.code === log.category)?.color || '#FFF' }]}>
                        {log.category.toUpperCase()}
                      </Text>
                    </View>
                  </View>
                  <Text style={[styles.logDesc, isRtl && styles.rtlText]}>{log.description}</Text>
                </GlassCard>
              );
            })}
          </View>
        )}

        <View style={{ height: 100 }} />
      </ScrollView>
    </View>
  );
};

const styles = StyleSheet.create({
  outerContainer: {
    flex: 1,
    backgroundColor: COLORS.background,
  },
  container: {
    flex: 1,
    paddingHorizontal: 16,
    paddingTop: 20,
  },
  header: {
    marginBottom: 20,
    marginTop: Platform.OS === 'ios' ? 40 : 10,
  },
  headerTexts: {
    flex: 1,
  },
  title: {
    color: '#FFF',
    fontSize: 22,
    fontWeight: '900',
    letterSpacing: 2,
  },
  subtitle: {
    color: COLORS.textSecondary,
    fontSize: 12,
    marginTop: 4,
  },
  searchWrapper: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: 'rgba(255, 255, 255, 0.02)',
    borderColor: 'rgba(255, 255, 255, 0.05)',
    borderWidth: 1,
    borderRadius: 14,
    paddingHorizontal: 16,
    height: 48,
    marginBottom: 20,
  },
  searchIcon: {
    marginRight: 10,
  },
  searchInput: {
    flex: 1,
    color: '#FFF',
    fontSize: 13,
    height: '100%',
  } as any,
  catScroll: {
    marginBottom: 25,
  },
  catRow: {
    flexDirection: 'row',
  },
  catBadge: {
    paddingHorizontal: 14,
    paddingVertical: 8,
    borderRadius: 12,
    backgroundColor: 'rgba(255,255,255,0.01)',
    borderColor: 'rgba(255,255,255,0.04)',
    borderWidth: 1,
    marginRight: 8,
  },
  catBadgeActive: {
    borderWidth: 1,
  },
  catLabel: {
    color: COLORS.textSecondary,
    fontSize: 11,
    fontWeight: '700',
  },
  catLabelActive: {
    fontWeight: '900',
  },
  timelineList: {
    width: '100%',
  },
  logCard: {
    padding: 16,
    marginBottom: 12,
  },
  logHeaderRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 10,
  },
  logMetaLeft: {
    flexDirection: 'row',
    alignItems: 'center',
    flex: 1,
  },
  logIconBox: {
    width: 32,
    height: 32,
    borderRadius: 10,
    borderWidth: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  titleGroup: {
    marginLeft: 12,
  },
  logAction: {
    color: '#FFF',
    fontSize: 12,
    fontWeight: '800',
  },
  logTimestamp: {
    color: COLORS.textMuted,
    fontSize: 9,
    marginTop: 2,
  },
  categoryBadge: {
    backgroundColor: 'rgba(255,255,255,0.03)',
    borderRadius: 6,
    paddingHorizontal: 6,
    paddingVertical: 2,
  },
  categoryText: {
    fontSize: 8,
    fontWeight: '800',
    letterSpacing: 0.5,
  },
  logDesc: {
    color: COLORS.textSecondary,
    fontSize: 11,
    lineHeight: 16,
    marginTop: 4,
  },
  emptyContainer: {
    padding: 50,
    alignItems: 'center',
  },
  emptyText: {
    color: COLORS.textSecondary,
    fontSize: 13,
  },
  simCard: {
    padding: 16,
    marginBottom: 20,
    borderColor: 'rgba(0, 255, 102, 0.1)',
  },
  simTitle: {
    color: '#FFF',
    fontSize: 13,
    fontWeight: '800',
    marginBottom: 4,
  },
  simDesc: {
    color: COLORS.textSecondary,
    fontSize: 11,
    lineHeight: 16,
    marginBottom: 12,
  },
  simActionsRow: {
    flexDirection: 'row',
  },
  simBtn: {
    backgroundColor: COLORS.primary,
    height: 36,
    borderRadius: 8,
    paddingHorizontal: 12,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    marginRight: 10,
  },
  simBtnText: {
    color: '#000',
    fontSize: 10,
    fontWeight: '900',
    letterSpacing: 0.5,
  },
  clearBtn: {
    borderColor: 'rgba(239, 68, 68, 0.2)',
    borderWidth: 1,
    backgroundColor: 'rgba(239, 68, 68, 0.03)',
    height: 36,
    borderRadius: 8,
    paddingHorizontal: 12,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
  },
  clearBtnText: {
    color: '#EF4444',
    fontSize: 10,
    fontWeight: '900',
    letterSpacing: 0.5,
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
