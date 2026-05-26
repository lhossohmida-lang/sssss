import React, { useState } from 'react';
import { View, Text, StyleSheet, ScrollView, TouchableOpacity, Modal, Platform } from 'react-native';
import { COLORS } from '../theme/colors';
import { useAppStore } from '../store/useAppStore';
import { PremiumVisaCard } from '../components/PremiumVisaCard';
import { GlassCard } from '../components/GlassCard';
import { translations } from '../theme/translations';
import { Shield, ShieldOff, Eye, EyeOff, Sliders, CreditCard, Zap, ChevronRight, ChevronLeft, Info, X, Copy } from 'lucide-react';

export const VirtualCardScreen: React.FC = () => {
  const { cards, toggleFreezeCard, toggleCardDetails, updateCardLimit, addCard, language } = useAppStore();
  const [selectedCardId, setSelectedCardId] = useState(cards[0]?.id || '');
  const [showDetailsModal, setShowDetailsModal] = useState(false);
  const selectedCard = cards.find(c => c.id === selectedCardId) || cards[0];

  const t = (key: string) => translations[language]?.[key] || translations['en']?.[key] || key;
  const isRtl = language === 'ar';

  const handleCreateCard = (design: 'premium' | 'neon') => {
    addCard({
      holder: 'ALEXANDER MOREAU',
      brand: 'Visa',
      type: 'Virtual',
      spendingLimit: 5000,
      color: '#71717A',
      design,
      isFrozen: false,
      showDetails: false,
    });
  };

  if (!selectedCard) {
    return (
      <View style={styles.emptyContainer}>
        <Text style={styles.emptyText}>{isRtl ? 'لا توجد بطاقات.' : 'No cards available.'}</Text>
      </View>
    );
  }

  return (
    <ScrollView style={styles.container} showsVerticalScrollIndicator={false}>

      {/* Header */}
      <View style={[styles.header, isRtl && styles.rtlRow]}>
        <Text style={styles.title}>{isRtl ? 'بطاقاتي' : 'Cards'}</Text>
        {cards.length > 1 && (
          <ScrollView horizontal showsHorizontalScrollIndicator={false}>
            <View style={[styles.switcherRow, isRtl && styles.rtlRow]}>
              {cards.map((c) => (
                <TouchableOpacity
                  key={c.id}
                  onPress={() => setSelectedCardId(c.id)}
                  style={[styles.switcherItem, c.id === selectedCard.id && styles.switcherItemActive]}
                >
                  <Text style={[styles.switcherText, c.id === selectedCard.id && styles.switcherTextActive]}>
                    •••• {c.number.slice(-4)}
                  </Text>
                </TouchableOpacity>
              ))}
            </View>
          </ScrollView>
        )}
      </View>

      {/* Add label hint */}
      <Text style={[styles.addLabel, isRtl && styles.rtlText]}>
        {isRtl ? 'أضف تسمية للبطاقة ✎' : 'Add a card label ✎'}
      </Text>

      {/* Grey-Style Card */}
      <PremiumVisaCard
        card={selectedCard}
        onToggleFreeze={() => toggleFreezeCard(selectedCard.id)}
        onToggleDetails={() => toggleCardDetails(selectedCard.id)}
      />

      {/* ── 3 Action Buttons: Details | Freeze | Show PIN ── */}
      <View style={[styles.actionRow, isRtl && styles.rtlRow]}>
        <TouchableOpacity style={styles.actionBtn} onPress={() => setShowDetailsModal(true)}>
          <View style={styles.actionCircle}>
            <Info size={20} color="#FFF" />
          </View>
          <Text style={styles.actionLabel}>{isRtl ? 'التفاصيل' : 'Details'}</Text>
        </TouchableOpacity>

        <TouchableOpacity style={styles.actionBtn} onPress={() => toggleFreezeCard(selectedCard.id)}>
          <View style={[styles.actionCircle, selectedCard.isFrozen && styles.actionCircleActive]}>
            {selectedCard.isFrozen
              ? <ShieldOff size={20} color="#60a5fa" />
              : <Shield size={20} color="#FFF" />}
          </View>
          <Text style={styles.actionLabel}>{isRtl ? 'تجميد' : 'Freeze'}</Text>
        </TouchableOpacity>

        <TouchableOpacity style={styles.actionBtn} onPress={() => toggleCardDetails(selectedCard.id)}>
          <View style={[styles.actionCircle, selectedCard.showDetails && styles.actionCircleActive]}>
            {selectedCard.showDetails
              ? <EyeOff size={20} color="#60a5fa" />
              : <Eye size={20} color="#FFF" />}
          </View>
          <Text style={styles.actionLabel}>{isRtl ? 'عرض الـ PIN' : 'Show PIN'}</Text>
        </TouchableOpacity>
      </View>

      {/* ── Manage Card ── */}
      <Text style={[styles.sectionTitle, isRtl && styles.rtlText]}>
        {isRtl ? 'إدارة البطاقة' : 'MANAGE CARD'}
      </Text>

      <GlassCard style={styles.manageCard}>
        <TouchableOpacity style={[styles.manageRow, isRtl && styles.rtlRow]}>
          <View style={styles.manageIconWrap}>
            <Sliders size={18} color="#FFF" />
          </View>
          <Text style={[styles.manageRowText, isRtl && { marginRight: 14, marginLeft: 0 }]}>
            {isRtl ? 'حدود الإنفاق' : 'Payment limits'}
          </Text>
          {isRtl ? <ChevronLeft size={16} color="rgba(255,255,255,0.3)" /> : <ChevronRight size={16} color="rgba(255,255,255,0.3)" />}
        </TouchableOpacity>

        <View style={styles.divider} />

        <TouchableOpacity style={[styles.manageRow, isRtl && styles.rtlRow]}>
          <View style={styles.manageIconWrap}>
            <CreditCard size={18} color="#FFF" />
          </View>
          <Text style={[styles.manageRowText, isRtl && { marginRight: 14, marginLeft: 0 }]}>
            {isRtl ? 'كشف البطاقة' : 'Card statement'}
          </Text>
          {isRtl ? <ChevronLeft size={16} color="rgba(255,255,255,0.3)" /> : <ChevronRight size={16} color="rgba(255,255,255,0.3)" />}
        </TouchableOpacity>

        {Platform.OS === 'web' && (
          <>
            <View style={styles.divider} />
            <View style={{ padding: 16 }}>
              <View style={[styles.limitHeaderRow, isRtl && styles.rtlRow]}>
                <Text style={styles.limitLabel}>{isRtl ? 'سقف الإنفاق الشهري' : 'SPENDING LIMIT'}</Text>
                <Text style={styles.limitVal}>${selectedCard.spendingLimit.toLocaleString()}</Text>
              </View>
              <input
                type="range"
                min="500"
                max="15000"
                step="250"
                value={selectedCard.spendingLimit}
                onChange={(e) => updateCardLimit(selectedCard.id, parseFloat(e.target.value))}
                style={{ width: '100%', cursor: 'pointer', accentColor: '#6366f1', margin: '10px 0' }}
              />
            </View>
          </>
        )}
      </GlassCard>

      {/* Generate Cards */}
      <Text style={[styles.sectionTitle, isRtl && styles.rtlText, { marginTop: 24 }]}>
        {t('CARD_GENERATE')}
      </Text>
      <View style={[styles.genRow, isRtl && styles.rtlRow]}>
        <TouchableOpacity onPress={() => handleCreateCard('premium')} style={[styles.genBtn, isRtl && styles.rtlRow]}>
          <CreditCard size={16} color="#FFF" style={isRtl ? { marginLeft: 8 } : { marginRight: 8 }} />
          <Text style={styles.genBtnText}>{t('CARD_GENERATE_PLATINUM')}</Text>
        </TouchableOpacity>
        <TouchableOpacity onPress={() => handleCreateCard('neon')} style={[styles.genBtn, isRtl && styles.rtlRow]}>
          <Zap size={16} color="#FFF" style={isRtl ? { marginLeft: 8 } : { marginRight: 8 }} />
          <Text style={styles.genBtnText}>{t('CARD_GENERATE_NEON')}</Text>
        </TouchableOpacity>
      </View>

      <View style={{ height: 100 }} />

      {/* ── Card Details Modal ── */}
      <Modal visible={showDetailsModal} transparent animationType="slide" onRequestClose={() => setShowDetailsModal(false)}>
        <View style={styles.modalOverlay}>
          <View style={styles.modalSheet}>
            <View style={[styles.modalHeader, isRtl && styles.rtlRow]}>
              <Text style={styles.modalTitle}>{isRtl ? 'تفاصيل البطاقة' : 'Card Details'}</Text>
              <TouchableOpacity onPress={() => setShowDetailsModal(false)}>
                <X size={22} color="rgba(255,255,255,0.6)" />
              </TouchableOpacity>
            </View>

            {[
              { label: isRtl ? 'اسم حامل البطاقة' : 'Card name', value: selectedCard.holder },
              { label: isRtl ? 'رقم البطاقة' : 'Card number', value: selectedCard.showDetails ? selectedCard.number : `•••• •••• •••• ${selectedCard.number.slice(-4)}` },
              { label: 'CVV', value: selectedCard.showDetails ? selectedCard.cvv : '•••' },
              { label: isRtl ? 'تاريخ الانتهاء' : 'Expiry date', value: selectedCard.expiry },
            ].map((item, idx) => (
              <View key={idx} style={[styles.detailRow, isRtl && styles.rtlRow]}>
                <View style={isRtl ? { alignItems: 'flex-end' } : undefined}>
                  <Text style={styles.detailLabel}>{item.label}</Text>
                  <Text style={styles.detailValue}>{item.value}</Text>
                </View>
                <TouchableOpacity style={styles.copyCircle}>
                  <Copy size={14} color="rgba(255,255,255,0.5)" />
                </TouchableOpacity>
              </View>
            ))}

            <TouchableOpacity style={styles.revealBtn} onPress={() => toggleCardDetails(selectedCard.id)}>
              <Text style={styles.revealBtnText}>
                {selectedCard.showDetails
                  ? (isRtl ? 'إخفاء التفاصيل' : 'Hide details')
                  : (isRtl ? 'عرض التفاصيل' : 'About this card')}
              </Text>
            </TouchableOpacity>
          </View>
        </View>
      </Modal>
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
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: 4,
    marginTop: Platform.OS === 'ios' ? 40 : 10,
  },
  title: { color: '#FFF', fontSize: 20, fontWeight: '800' },
  addLabel: { color: 'rgba(255,255,255,0.35)', fontSize: 12, textAlign: 'center', marginBottom: 2 },

  switcherRow: { flexDirection: 'row' },
  switcherItem: {
    paddingHorizontal: 14, paddingVertical: 6, borderRadius: 10,
    backgroundColor: 'rgba(255,255,255,0.02)', borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.05)', marginLeft: 8,
  },
  switcherItemActive: { backgroundColor: 'rgba(255,255,255,0.08)', borderColor: 'rgba(255,255,255,0.2)' },
  switcherText: { color: COLORS.textSecondary, fontSize: 11, fontWeight: '700' },
  switcherTextActive: { color: '#FFF' },

  // 3 action buttons
  actionRow: { flexDirection: 'row', justifyContent: 'center', gap: 44, marginTop: 4, marginBottom: 30 },
  actionBtn: { alignItems: 'center', gap: 8 },
  actionCircle: {
    width: 54, height: 54, borderRadius: 27,
    backgroundColor: 'rgba(255,255,255,0.07)',
    borderWidth: 1, borderColor: 'rgba(255,255,255,0.1)',
    justifyContent: 'center', alignItems: 'center',
  },
  actionCircleActive: { backgroundColor: 'rgba(96,165,250,0.12)', borderColor: 'rgba(96,165,250,0.3)' },
  actionLabel: { color: 'rgba(255,255,255,0.6)', fontSize: 12, fontWeight: '600' },

  sectionTitle: {
    color: 'rgba(255,255,255,0.35)', fontSize: 11, fontWeight: '800',
    letterSpacing: 1.5, marginBottom: 12, textTransform: 'uppercase',
  },

  manageCard: { padding: 0, overflow: 'hidden' },
  manageRow: { flexDirection: 'row', alignItems: 'center', padding: 16 },
  manageIconWrap: {
    width: 34, height: 34, borderRadius: 10,
    backgroundColor: 'rgba(255,255,255,0.05)',
    justifyContent: 'center', alignItems: 'center', marginRight: 14,
  },
  manageRowText: { color: '#FFF', fontSize: 14, fontWeight: '500', flex: 1 },
  divider: { height: 1, backgroundColor: 'rgba(255,255,255,0.05)', marginHorizontal: 16 },

  limitHeaderRow: { flexDirection: 'row', alignItems: 'center', marginBottom: 6 },
  limitLabel: { color: 'rgba(255,255,255,0.4)', fontSize: 10, fontWeight: '800', letterSpacing: 1, flex: 1 },
  limitVal: { color: '#FFF', fontSize: 15, fontWeight: '700' },

  genRow: { flexDirection: 'row', justifyContent: 'space-between', marginBottom: 20 },
  genBtn: {
    flex: 1, flexDirection: 'row', alignItems: 'center', justifyContent: 'center',
    backgroundColor: 'rgba(255,255,255,0.04)', borderColor: 'rgba(255,255,255,0.08)',
    borderWidth: 1, height: 46, borderRadius: 12, marginHorizontal: 4,
  },
  genBtnText: { color: '#FFF', fontSize: 11, fontWeight: '700' },

  emptyContainer: { flex: 1, justifyContent: 'center', alignItems: 'center', backgroundColor: COLORS.background },
  emptyText: { color: COLORS.textSecondary, fontSize: 16 },

  // Modal
  modalOverlay: { flex: 1, backgroundColor: 'rgba(0,0,0,0.75)', justifyContent: 'flex-end' },
  modalSheet: {
    backgroundColor: '#111114', borderTopLeftRadius: 24, borderTopRightRadius: 24,
    padding: 24, borderTopWidth: 1, borderColor: 'rgba(255,255,255,0.06)',
  },
  modalHeader: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 22 },
  modalTitle: { color: '#FFF', fontSize: 18, fontWeight: '700' },
  detailRow: {
    flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center',
    paddingVertical: 14, borderBottomWidth: 1, borderBottomColor: 'rgba(255,255,255,0.05)',
  },
  detailLabel: { color: 'rgba(255,255,255,0.4)', fontSize: 11, marginBottom: 4 },
  detailValue: { color: '#FFF', fontSize: 15, fontWeight: '500', letterSpacing: 0.5 },
  copyCircle: {
    width: 32, height: 32, borderRadius: 16,
    backgroundColor: 'rgba(255,255,255,0.05)', justifyContent: 'center', alignItems: 'center',
  },
  revealBtn: { backgroundColor: '#4338ca', height: 50, borderRadius: 14, justifyContent: 'center', alignItems: 'center', marginTop: 20 },
  revealBtnText: { color: '#FFF', fontSize: 14, fontWeight: '700' },

  rtlRow: { flexDirection: 'row-reverse' },
  rtlAlign: { alignItems: 'flex-end' },
  rtlText: { textAlign: 'right' },
});
