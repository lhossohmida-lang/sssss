import React from 'react';
import { View, Text, StyleSheet, TouchableOpacity, Clipboard, ToastAndroid, Platform } from 'react-native';
import { COLORS } from '../theme/colors';
import { useAppStore, Card } from '../store/useAppStore';
import { Eye, EyeOff, Copy, Shield, ShieldAlert, Award } from 'lucide-react';

interface PremiumVisaCardProps {
  card: Card;
  onToggleFreeze?: () => void;
  onToggleDetails?: () => void;
}

export const PremiumVisaCard: React.FC<PremiumVisaCardProps> = ({ card, onToggleFreeze, onToggleDetails }) => {
  const toggleCardDetails = useAppStore((state) => state.toggleCardDetails);
  
  const handleCopyNumber = () => {
    Clipboard.setString(card.number.replace(/\s/g, ''));
    if (Platform.OS === 'android') {
      ToastAndroid.show('Card number copied!', ToastAndroid.SHORT);
    } else if (Platform.OS === 'web') {
      alert('Card number copied to clipboard!');
    }
  };

  const getCardGradient = () => {
    if (card.design === 'premium') return ['#18181B', '#27272A', '#09090B'];
    if (card.design === 'neon') return ['#064E3B', '#111827', '#022C22'];
    return ['#3B0764', '#1E1B4B', '#0F172A'];
  };

  const gradientColors = getCardGradient();

  return (
    <View style={[
      styles.cardContainer,
      { shadowColor: card.isFrozen ? '#000' : card.color },
      card.isFrozen && styles.frozenCard
    ]}>
      {/* Background stylized vectors */}
      <View style={[styles.gradientLayer, { backgroundColor: gradientColors[0] }]} />
      <View style={[styles.glowOrb, { backgroundColor: card.isFrozen ? '#333' : card.color, left: -20, top: -20 }]} />
      <View style={[styles.glowOrb, { backgroundColor: '#111', right: -40, bottom: -40 }]} />

      {/* Card Contents */}
      <View style={styles.cardHeader}>
        <View>
          <Text style={styles.brandText}>GRYE <Text style={{ color: COLORS.primary, fontWeight: '900' }}>PREMIUM</Text></Text>
          <Text style={styles.cardTypeText}>{card.type.toUpperCase()}</Text>
        </View>
        <Award size={28} color={card.isFrozen ? '#666' : COLORS.primary} style={styles.chipIcon} />
      </View>

      {/* Chip & NFC symbol */}
      <View style={styles.chipSection}>
        <View style={styles.goldChip}>
          <View style={styles.chipGrid} />
        </View>
        <View style={styles.nfcSymbol}>
          <View style={styles.nfcWave} />
          <View style={[styles.nfcWave, { opacity: 0.7 }]} />
          <View style={[styles.nfcWave, { opacity: 0.4 }]} />
        </View>
      </View>

      {/* Card Number */}
      <TouchableOpacity activeOpacity={0.7} onPress={handleCopyNumber} style={styles.numberRow}>
        <Text style={styles.cardNumber}>
          {card.showDetails ? card.number : `••••  ••••  ••••  ${card.number.slice(-4)}`}
        </Text>
        <Copy size={16} color="rgba(255,255,255,0.4)" style={styles.copyIcon} />
      </TouchableOpacity>

      {/* Expiry & CVV */}
      <View style={styles.cardFooter}>
        <View>
          <Text style={styles.label}>CARDHOLDER</Text>
          <Text style={styles.holderName}>{card.holder}</Text>
        </View>

        <View style={styles.footerRight}>
          <View style={{ marginRight: 24 }}>
            <Text style={styles.label}>EXPIRES</Text>
            <Text style={styles.footerVal}>{card.expiry}</Text>
          </View>
          <TouchableOpacity 
            activeOpacity={0.7} 
            onPress={() => onToggleDetails ? onToggleDetails() : toggleCardDetails(card.id)}
            style={styles.cvvContainer}
          >
            <View>
              <Text style={[styles.label, { textAlign: 'right' }]}>CVV</Text>
              <Text style={[styles.footerVal, { textAlign: 'right' }]}>
                {card.showDetails ? card.cvv : '•••'}
              </Text>
            </View>
            {card.showDetails ? (
              <EyeOff size={16} color={COLORS.primary} style={styles.eyeIcon} />
            ) : (
              <Eye size={16} color="rgba(255,255,255,0.6)" style={styles.eyeIcon} />
            )}
          </TouchableOpacity>
        </View>
      </View>

      {/* Frozen Overlay */}
      {card.isFrozen && (
        <View style={styles.frozenOverlay}>
          <ShieldAlert size={40} color="#EF4444" />
          <Text style={styles.frozenText}>CARD FROZEN</Text>
          <Text style={styles.frozenSubtext}>Tap unfreeze in dashboard to resume payments</Text>
        </View>
      )}
    </View>
  );
};

const styles = StyleSheet.create({
  cardContainer: {
    height: 220,
    width: '100%',
    maxWidth: 380,
    borderRadius: 24,
    padding: 24,
    position: 'relative',
    overflow: 'hidden',
    shadowOffset: { width: 0, height: 10 },
    shadowOpacity: 0.4,
    shadowRadius: 20,
    elevation: 8,
    alignSelf: 'center',
    marginVertical: 15,
  },
  gradientLayer: {
    ...StyleSheet.absoluteFillObject,
    opacity: 0.95,
  },
  glowOrb: {
    position: 'absolute',
    width: 200,
    height: 200,
    borderRadius: 100,
    opacity: 0.12,
  },
  frozenCard: {
    opacity: 0.8,
  },
  cardHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  brandText: {
    color: '#FFF',
    fontSize: 18,
    fontWeight: '800',
    letterSpacing: 2,
  },
  cardTypeText: {
    color: 'rgba(255,255,255,0.4)',
    fontSize: 10,
    fontWeight: '700',
    letterSpacing: 1.5,
    marginTop: 2,
  },
  chipIcon: {
    opacity: 0.8,
  },
  chipSection: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: 18,
    marginBottom: 10,
  },
  goldChip: {
    width: 44,
    height: 32,
    backgroundColor: '#F59E0B',
    borderRadius: 6,
    borderWidth: 1,
    borderColor: '#D97706',
    position: 'relative',
    overflow: 'hidden',
    opacity: 0.85,
  },
  chipGrid: {
    width: '100%',
    height: '100%',
    borderColor: 'rgba(0,0,0,0.2)',
    borderWidth: 1,
    position: 'absolute',
    top: '30%',
    left: '20%',
  },
  nfcSymbol: {
    marginLeft: 12,
    flexDirection: 'row',
    alignItems: 'center',
  },
  nfcWave: {
    width: 3,
    height: 12,
    backgroundColor: '#FFF',
    marginHorizontal: 1,
    borderRadius: 2,
  },
  numberRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginVertical: 12,
  },
  cardNumber: {
    color: '#FFF',
    fontSize: 20,
    fontWeight: '600',
    letterSpacing: 3,
    fontFamily: Platform.OS === 'ios' ? 'Courier New' : 'monospace',
  },
  copyIcon: {
    marginLeft: 10,
    opacity: 0.7,
  },
  cardFooter: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-end',
    marginTop: 'auto',
  },
  label: {
    color: 'rgba(255,255,255,0.4)',
    fontSize: 8,
    fontWeight: '700',
    letterSpacing: 1.5,
    marginBottom: 4,
  },
  holderName: {
    color: '#FFF',
    fontSize: 13,
    fontWeight: '700',
    letterSpacing: 1,
  },
  footerRight: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  footerVal: {
    color: '#FFF',
    fontSize: 13,
    fontWeight: '700',
    letterSpacing: 1,
  },
  cvvContainer: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  eyeIcon: {
    marginLeft: 6,
    marginTop: 10,
  },
  frozenOverlay: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: 'rgba(10, 10, 12, 0.92)',
    justifyContent: 'center',
    alignItems: 'center',
    padding: 20,
  },
  frozenText: {
    color: '#EF4444',
    fontSize: 18,
    fontWeight: '800',
    letterSpacing: 2,
    marginTop: 12,
  },
  frozenSubtext: {
    color: '#9CA3AF',
    fontSize: 12,
    textAlign: 'center',
    marginTop: 4,
  }
});
