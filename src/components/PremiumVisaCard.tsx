import React from 'react';
import { View, Text, StyleSheet, TouchableOpacity, Platform } from 'react-native';
import { COLORS } from '../theme/colors';
import { useAppStore, Card } from '../store/useAppStore';
import { Eye, EyeOff, ShieldAlert, Wifi } from 'lucide-react';

interface PremiumVisaCardProps {
  card: Card;
  onToggleFreeze?: () => void;
  onToggleDetails?: () => void;
}

export const PremiumVisaCard: React.FC<PremiumVisaCardProps> = ({ card, onToggleFreeze, onToggleDetails }) => {
  const toggleCardDetails = useAppStore((state) => state.toggleCardDetails);

  const handleCopyNumber = () => {
    if (Platform.OS === 'web') {
      navigator.clipboard?.writeText(card.number.replace(/\s/g, ''));
      alert('Card number copied to clipboard!');
    }
  };

  // Grey-style card: dark navy with purple gradient, matching app.grey.co
  const cardBg1 = card.isFrozen ? '#1a1a1a' : '#1a1a2e';
  const cardBg2 = card.isFrozen ? '#0d0d0d' : '#16213e';
  const cardAccent = card.isFrozen ? '#2a2a2a' : '#2d2b55';

  return (
    <View style={[styles.cardWrapper]}>
      <View style={[
        styles.cardContainer,
        card.isFrozen && styles.frozenCard
      ]}>
        {/* Card background layers */}
        <View style={[styles.bgBase, { backgroundColor: cardBg1 }]} />
        {/* Purple gradient orb - top right */}
        <View style={[styles.orb, styles.orbTopRight, { backgroundColor: card.isFrozen ? '#1a1a1a' : '#312e81' }]} />
        {/* Subtle orb - bottom left */}
        <View style={[styles.orb, styles.orbBottomLeft, { backgroundColor: card.isFrozen ? '#111' : '#1e1b4b' }]} />
        {/* Shine stripe */}
        <View style={styles.shineStripe} />

        {/* ── TOP ROW: Grey logo + VISA ── */}
        <View style={styles.topRow}>
          <View style={styles.greyLogoWrap}>
            <Text style={styles.greyLogoText}>
              <Text style={styles.greyLogoIcon}>✦ </Text>
              Grey
            </Text>
          </View>

          <View style={styles.visaWrap}>
            <Text style={styles.visaText}>VISA</Text>
            <Text style={styles.visaSubText}>P2I num</Text>
          </View>
        </View>

        {/* ── MIDDLE: NFC / Contactless icon ── */}
        <View style={styles.nfcRow}>
          <Wifi size={18} color="rgba(255,255,255,0.35)" style={styles.nfcIcon as any} />
        </View>

        {/* ── BOTTOM ROW: Card number + eye toggle ── */}
        <View style={styles.bottomRow}>
          <TouchableOpacity activeOpacity={0.7} onPress={handleCopyNumber} style={styles.cardNumberWrap}>
            <Text style={styles.cardNumberText}>
              {card.showDetails
                ? card.number
                : `••••  ••••  ••••  ${card.number.slice(-4)}`}
            </Text>
          </TouchableOpacity>

          <TouchableOpacity
            activeOpacity={0.7}
            onPress={() => onToggleDetails ? onToggleDetails() : toggleCardDetails(card.id)}
            style={styles.eyeBtn}
          >
            {card.showDetails
              ? <EyeOff size={16} color="rgba(255,255,255,0.5)" />
              : <Eye size={16} color="rgba(255,255,255,0.5)" />
            }
          </TouchableOpacity>
        </View>

        {/* ── CARDHOLDER name line ── */}
        <View style={styles.holderRow}>
          <Text style={styles.holderLabel}>CARDHOLDER</Text>
          <Text style={styles.holderName}>{card.holder}</Text>
        </View>

        {/* ── Expiry / CVV row ── */}
        <View style={styles.metaRow}>
          <View>
            <Text style={styles.metaLabel}>EXPIRES</Text>
            <Text style={styles.metaValue}>{card.expiry}</Text>
          </View>
          <View>
            <Text style={[styles.metaLabel, { textAlign: 'right' }]}>CVV</Text>
            <Text style={[styles.metaValue, { textAlign: 'right' }]}>
              {card.showDetails ? card.cvv : '•••'}
            </Text>
          </View>
        </View>

        {/* ── Frozen Overlay ── */}
        {card.isFrozen && (
          <View style={styles.frozenOverlay}>
            <ShieldAlert size={36} color="#EF4444" />
            <Text style={styles.frozenText}>CARD FROZEN</Text>
            <Text style={styles.frozenSubtext}>Tap unfreeze to resume payments</Text>
          </View>
        )}
      </View>

      {/* Card shadow glow */}
      {!card.isFrozen && <View style={styles.cardGlow} />}
    </View>
  );
};

const styles = StyleSheet.create({
  cardWrapper: {
    alignSelf: 'center',
    width: '100%',
    maxWidth: 400,
    marginVertical: 16,
  },

  // Main card surface
  cardContainer: {
    height: 218,
    borderRadius: 20,
    padding: 22,
    position: 'relative',
    overflow: 'hidden',
    // Card border like Grey's subtle white edge
    borderWidth: 1,
    borderColor: 'rgba(255, 255, 255, 0.08)',
    shadowColor: '#312e81',
    shadowOffset: { width: 0, height: 12 },
    shadowOpacity: 0.45,
    shadowRadius: 28,
    elevation: 12,
  },

  bgBase: {
    ...StyleSheet.absoluteFillObject,
  },

  // Purple glow orb top-right (Grey signature look)
  orb: {
    position: 'absolute',
    borderRadius: 999,
    opacity: 0.55,
  },
  orbTopRight: {
    width: 220,
    height: 220,
    top: -80,
    right: -60,
  },
  orbBottomLeft: {
    width: 160,
    height: 160,
    bottom: -60,
    left: -40,
    opacity: 0.3,
  },

  // Diagonal light shine
  shineStripe: {
    position: 'absolute',
    width: 2,
    height: 400,
    backgroundColor: 'rgba(255,255,255,0.025)',
    top: -80,
    left: '45%',
    transform: [{ rotate: '-35deg' }],
  },

  frozenCard: {
    opacity: 0.75,
  },

  // TOP ROW
  topRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
  },
  greyLogoWrap: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  greyLogoIcon: {
    color: '#a5b4fc',
    fontSize: 14,
  },
  greyLogoText: {
    color: '#FFFFFF',
    fontSize: 20,
    fontWeight: '700',
    letterSpacing: 0.5,
    fontFamily: Platform.OS === 'ios' ? 'Georgia' : 'serif',
  },
  visaWrap: {
    alignItems: 'flex-end',
  },
  visaText: {
    color: '#FFFFFF',
    fontSize: 22,
    fontWeight: '900',
    letterSpacing: 1,
    fontFamily: Platform.OS === 'ios' ? 'Georgia' : 'serif',
    fontStyle: 'italic',
  },
  visaSubText: {
    color: 'rgba(255,255,255,0.35)',
    fontSize: 9,
    letterSpacing: 0.5,
    marginTop: 1,
  },

  // NFC
  nfcRow: {
    marginTop: 14,
    marginBottom: 2,
  },
  nfcIcon: {
    transform: [{ rotate: '90deg' }],
  },

  // Card Number
  bottomRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginTop: 14,
  },
  cardNumberWrap: {
    flex: 1,
  },
  cardNumberText: {
    color: '#FFFFFF',
    fontSize: 18,
    fontWeight: '500',
    letterSpacing: 3,
    fontFamily: Platform.OS === 'ios' ? 'Courier New' : 'monospace',
  },
  eyeBtn: {
    padding: 6,
    marginLeft: 8,
  },

  // Holder row
  holderRow: {
    marginTop: 12,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  holderLabel: {
    color: 'rgba(255,255,255,0.3)',
    fontSize: 8,
    fontWeight: '700',
    letterSpacing: 1.5,
  },
  holderName: {
    color: 'rgba(255,255,255,0.85)',
    fontSize: 12,
    fontWeight: '600',
    letterSpacing: 0.8,
    textTransform: 'uppercase',
  },

  // Meta row (expiry + cvv)
  metaRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginTop: 4,
  },
  metaLabel: {
    color: 'rgba(255,255,255,0.3)',
    fontSize: 8,
    fontWeight: '700',
    letterSpacing: 1.5,
    marginBottom: 2,
  },
  metaValue: {
    color: 'rgba(255,255,255,0.85)',
    fontSize: 13,
    fontWeight: '600',
    letterSpacing: 1,
  },

  // Frozen overlay
  frozenOverlay: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: 'rgba(10, 10, 14, 0.92)',
    justifyContent: 'center',
    alignItems: 'center',
    borderRadius: 20,
  },
  frozenText: {
    color: '#EF4444',
    fontSize: 16,
    fontWeight: '800',
    letterSpacing: 2,
    marginTop: 10,
  },
  frozenSubtext: {
    color: '#6B7280',
    fontSize: 11,
    textAlign: 'center',
    marginTop: 4,
  },

  // Bottom glow under the card
  cardGlow: {
    position: 'absolute',
    bottom: -18,
    left: '15%',
    right: '15%',
    height: 30,
    backgroundColor: '#4338ca',
    borderRadius: 50,
    opacity: 0.25,
    ...(Platform.OS === 'web' ? { filter: 'blur(18px)' } as any : {}),
  },
});
