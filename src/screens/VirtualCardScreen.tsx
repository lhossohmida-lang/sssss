import React, { useState } from 'react';
import { View, Text, StyleSheet, ScrollView, TouchableOpacity, Platform } from 'react-native';
import { COLORS } from '../theme/colors';
import { useAppStore, Card } from '../store/useAppStore';
import { PremiumVisaCard } from '../components/PremiumVisaCard';
import { GlassCard } from '../components/GlassCard';
import { Shield, ShieldOff, Eye, Sliders, Lock, Zap, CreditCard, ChevronRight } from 'lucide-react';

export const VirtualCardScreen: React.FC = () => {
  const { cards, toggleFreezeCard, toggleCardDetails, updateCardLimit, addCard } = useAppStore();
  const [selectedCardId, setSelectedCardId] = useState(cards[0]?.id || '');
  const selectedCard = cards.find(c => c.id === selectedCardId) || cards[0];

  const handleCreateCard = (design: 'premium' | 'neon') => {
    addCard({
      holder: 'ALEXANDER MOREAU',
      brand: 'Visa',
      type: 'Virtual',
      spendingLimit: 5000,
      color: design === 'premium' ? '#00FF66' : '#A855F7',
      design: design,
      isFrozen: false,
      showDetails: false
    });
    alert('Premium virtual card generated successfully!');
  };

  const handleSliderChange = (val: number) => {
    if (selectedCard) {
      updateCardLimit(selectedCard.id, Math.round(val));
    }
  };

  if (!selectedCard) {
    return (
      <View style={styles.emptyContainer}>
        <Text style={styles.emptyText}>No cards available.</Text>
      </View>
    );
  }

  return (
    <ScrollView style={styles.container} showsVerticalScrollIndicator={false}>
      <View style={styles.header}>
        <Text style={styles.title}>MY CARDS</Text>
        <Text style={styles.subtitle}>Manage your premium dynamic virtual credentials</Text>
      </View>

      {/* Primary Card View */}
      <PremiumVisaCard 
        card={selectedCard}
        onToggleFreeze={() => toggleFreezeCard(selectedCard.id)}
        onToggleDetails={() => toggleCardDetails(selectedCard.id)}
      />

      {/* Card Switcher Carousel */}
      <View style={styles.carouselWrapper}>
        <ScrollView horizontal showsHorizontalScrollIndicator={false} style={styles.switcherScroll}>
          {cards.map((c) => (
            <TouchableOpacity 
              key={c.id}
              onPress={() => setSelectedCardId(c.id)}
              style={[
                styles.switcherItem,
                c.id === selectedCard.id && styles.switcherItemActive
              ]}
            >
              <Text style={[
                styles.switcherText,
                c.id === selectedCard.id && styles.switcherTextActive
              ]}>
                * {c.number.slice(-4)} {c.isFrozen ? '(Frozen)' : ''}
              </Text>
            </TouchableOpacity>
          ))}
        </ScrollView>
      </View>

      {/* Card controls */}
      <Text style={styles.sectionTitle}>Card Settings</Text>
      
      <View style={styles.controlsGrid}>
        <GlassCard style={styles.controlBox}>
          <TouchableOpacity 
            activeOpacity={0.7} 
            onPress={() => toggleFreezeCard(selectedCard.id)}
            style={styles.controlBtnRow}
          >
            <View style={styles.controlIconLeft}>
              {selectedCard.isFrozen ? (
                <ShieldOff size={20} color={COLORS.success} />
              ) : (
                <Shield size={20} color={COLORS.danger} />
              )}
            </View>
            <View style={styles.controlMeta}>
              <Text style={styles.controlLabel}>
                {selectedCard.isFrozen ? 'Unfreeze Card' : 'Freeze Card'}
              </Text>
              <Text style={styles.controlDesc}>
                {selectedCard.isFrozen ? 'Resume authorization' : 'Instantly block all spends'}
              </Text>
            </View>
            <ChevronRight size={16} color="rgba(255,255,255,0.3)" />
          </TouchableOpacity>
        </GlassCard>

        <GlassCard style={styles.controlBox}>
          <TouchableOpacity 
            activeOpacity={0.7} 
            onPress={() => toggleCardDetails(selectedCard.id)}
            style={styles.controlBtnRow}
          >
            <View style={styles.controlIconLeft}>
              <Eye size={20} color={COLORS.primary} />
            </View>
            <View style={styles.controlMeta}>
              <Text style={styles.controlLabel}>Show Card Details</Text>
              <Text style={styles.controlDesc}>Reveal complete card credentials</Text>
            </View>
            <ChevronRight size={16} color="rgba(255,255,255,0.3)" />
          </TouchableOpacity>
        </GlassCard>
      </View>

      {/* Card Spending Limit Controls */}
      <Text style={styles.sectionTitle}>Monthly Spend Limits</Text>
      <GlassCard style={styles.limitBox}>
        <View style={styles.limitHeader}>
          <Sliders size={20} color={COLORS.primary} />
          <Text style={styles.limitLabelText}>MONTHLY THRESHOLD</Text>
          <Text style={styles.limitVal}>
            ${selectedCard.spendingLimit.toLocaleString()}
          </Text>
        </View>

        {/* Custom pure HTML/Web slider check or Native rendering */}
        {Platform.OS === 'web' ? (
          <input 
            type="range" 
            min="500" 
            max="15000" 
            step="250"
            value={selectedCard.spendingLimit} 
            onChange={(e) => handleSliderChange(parseFloat(e.target.value))}
            style={{ width: '100%', margin: '15px 0', cursor: 'pointer', accentColor: COLORS.primary }}
          />
        ) : (
          <View style={styles.nativeSliderContainer}>
            <Text style={{color: '#9CA3AF', fontSize: 12}}>Adjust slider values inside active mobile simulator</Text>
          </View>
        )}

        <Text style={styles.limitDesc}>
          Limits apply to all dynamic online, swipe, and merchant transfers.
        </Text>
      </GlassCard>

      {/* Dynamic Card generator */}
      <Text style={styles.sectionTitle}>Generate New Card</Text>
      <View style={styles.genRow}>
        <TouchableOpacity onPress={() => handleCreateCard('premium')} style={styles.genBtn}>
          <CreditCard size={18} color="#00FF66" style={{ marginRight: 8 }} />
          <Text style={styles.genBtnText}>Virtual Platinum</Text>
        </TouchableOpacity>

        <TouchableOpacity onPress={() => handleCreateCard('neon')} style={[styles.genBtn, { borderColor: 'rgba(168, 85, 247, 0.3)' }]}>
          <Zap size={18} color="#A855F7" style={{ marginRight: 8 }} />
          <Text style={styles.genBtnText}>Neon Ultra</Text>
        </TouchableOpacity>
      </View>

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
  carouselWrapper: {
    marginVertical: 10,
  },
  switcherScroll: {
    flexDirection: 'row',
  },
  switcherItem: {
    paddingHorizontal: 16,
    paddingVertical: 8,
    borderRadius: 12,
    backgroundColor: 'rgba(255, 255, 255, 0.02)',
    borderColor: 'rgba(255, 255, 255, 0.05)',
    borderWidth: 1,
    marginRight: 10,
  },
  switcherItemActive: {
    backgroundColor: 'rgba(0, 255, 102, 0.08)',
    borderColor: 'rgba(0, 255, 102, 0.2)',
  },
  switcherText: {
    color: COLORS.textSecondary,
    fontSize: 11,
    fontWeight: '700',
  },
  switcherTextActive: {
    color: COLORS.primary,
  },
  sectionTitle: {
    color: '#FFF',
    fontSize: 15,
    fontWeight: '800',
    marginTop: 30,
    marginBottom: 16,
    letterSpacing: 1.5,
  },
  controlsGrid: {
    width: '100%',
  },
  controlBox: {
    padding: 16,
    marginBottom: 12,
  },
  controlBtnRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  controlIconLeft: {
    width: 40,
    height: 40,
    borderRadius: 12,
    backgroundColor: 'rgba(255, 255, 255, 0.04)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  controlMeta: {
    flex: 1,
    marginLeft: 14,
  },
  controlLabel: {
    color: '#FFF',
    fontSize: 13,
    fontWeight: '700',
  },
  controlDesc: {
    color: COLORS.textSecondary,
    fontSize: 10,
    marginTop: 2,
  },
  limitBox: {
    padding: 20,
  },
  limitHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 10,
  },
  limitLabelText: {
    color: COLORS.textSecondary,
    fontSize: 10,
    fontWeight: '900',
    letterSpacing: 1.5,
    marginLeft: 10,
    flex: 1,
  },
  limitVal: {
    color: '#FFF',
    fontSize: 16,
    fontWeight: '900',
  },
  nativeSliderContainer: {
    height: 40,
    justifyContent: 'center',
    alignItems: 'center',
  },
  limitDesc: {
    color: COLORS.textMuted,
    fontSize: 10,
    lineHeight: 16,
    marginTop: 10,
  },
  genRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginBottom: 20,
  },
  genBtn: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'rgba(255, 255, 255, 0.02)',
    borderColor: 'rgba(255, 255, 255, 0.05)',
    borderWidth: 1,
    height: 48,
    borderRadius: 12,
    marginHorizontal: 4,
  },
  genBtnText: {
    color: '#FFF',
    fontSize: 11,
    fontWeight: '800',
    letterSpacing: 0.5,
  },
  emptyContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: COLORS.background,
  },
  emptyText: {
    color: COLORS.textSecondary,
    fontSize: 16,
  }
});
