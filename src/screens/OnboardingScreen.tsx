import React, { useState } from 'react';
import { View, Text, StyleSheet, TouchableOpacity, Dimensions, Image, Platform } from 'react-native';
import { COLORS } from '../theme/colors';
import { GlassCard } from '../components/GlassCard';
import { Shield, Globe, Compass, Landmark } from 'lucide-react';

const { width } = Dimensions.get('window');

interface OnboardingScreenProps {
  onFinish: () => void;
}

export const OnboardingScreen: React.FC<OnboardingScreenProps> = ({ onFinish }) => {
  const [activeStep, setActiveStep] = useState(0);

  const steps = [
    {
      title: 'Global Banking without Borders',
      description: 'Open premium USD, EUR, and GBP multi-currency accounts instantly. Send, receive, and spend internationally with absolute freedom.',
      icon: <Globe size={48} color={COLORS.primary} />,
      gradient: COLORS.cardGradients.usd
    },
    {
      title: 'Premium Virtual Visa Cards',
      description: 'Issue highly secure 3D virtual Visa cards instantly. Freeze, unfreeze, and adjust spending controls directly from the palm of your hand.',
      icon: <Shield size={48} color={COLORS.primary} />,
      gradient: COLORS.cardGradients.premiumVisa
    },
    {
      title: 'Institutional Grade Security',
      description: 'Protected by industry-leading biometrics, smart transaction filters, and full compliance structures. Your capital is safe, always.',
      icon: <Landmark size={48} color={COLORS.primary} />,
      gradient: COLORS.cardGradients.eur
    }
  ];

  const handleNext = () => {
    if (activeStep < steps.length - 1) {
      setActiveStep(activeStep + 1);
    } else {
      onFinish();
    }
  };

  return (
    <View style={styles.container}>
      {/* Background radial glow */}
      <View style={styles.radialGlow} />

      {/* Brand logo */}
      <View style={styles.header}>
        <Text style={styles.brandTitle}>GRYE</Text>
        <Text style={styles.brandSub}>NEO-BANKING</Text>
      </View>

      {/* Cinematic Onboarding Core */}
      <View style={styles.carouselContainer}>
        <GlassCard glowing={true} style={styles.stepCard}>
          {/* Card background styling */}
          <View style={styles.cardHeaderGlow} />
          
          <View style={styles.iconWrapper}>
            {steps[activeStep].icon}
          </View>
          
          <Text style={styles.stepTitle}>{steps[activeStep].title}</Text>
          <Text style={styles.stepDesc}>{steps[activeStep].description}</Text>

          {/* Premium card illustration placeholder rendering beautifully */}
          <View style={styles.cardIllustration}>
            <View style={styles.illustrationOverlay} />
            <Text style={styles.illustrationText}>VISUAL STORYTELLING ACTIVE</Text>
          </View>
        </GlassCard>
      </View>

      {/* Stepper Dots */}
      <View style={styles.stepperContainer}>
        {steps.map((_, index) => (
          <View 
            key={index} 
            style={[
              styles.dot, 
              index === activeStep ? styles.activeDot : null
            ]} 
          />
        ))}
      </View>

      {/* Call to action */}
      <TouchableOpacity 
        activeOpacity={0.8} 
        onPress={handleNext} 
        style={styles.actionBtn}
      >
        <Text style={styles.actionBtnText}>
          {activeStep === steps.length - 1 ? 'GET STARTED' : 'CONTINUE'}
        </Text>
      </TouchableOpacity>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: COLORS.background,
    justifyContent: 'space-between',
    paddingVertical: 50,
    paddingHorizontal: 24,
  },
  radialGlow: {
    position: 'absolute',
    top: -150,
    left: -150,
    width: 500,
    height: 500,
    borderRadius: 250,
    backgroundColor: 'rgba(0, 255, 102, 0.05)',
    filter: Platform.OS === 'web' ? 'blur(100px)' : undefined,
  } as any,
  header: {
    alignItems: 'center',
    marginTop: 20,
  },
  brandTitle: {
    color: '#FFF',
    fontSize: 32,
    fontWeight: '900',
    letterSpacing: 8,
  },
  brandSub: {
    color: COLORS.primary,
    fontSize: 10,
    fontWeight: '900',
    letterSpacing: 4,
    marginTop: 4,
  },
  carouselContainer: {
    flex: 1,
    justifyContent: 'center',
    marginVertical: 30,
  },
  stepCard: {
    padding: 30,
    height: 380,
    justifyContent: 'center',
    alignItems: 'center',
    position: 'relative',
  },
  cardHeaderGlow: {
    position: 'absolute',
    top: 0,
    width: '100%',
    height: 4,
    backgroundColor: COLORS.primary,
  },
  iconWrapper: {
    width: 80,
    height: 80,
    borderRadius: 40,
    backgroundColor: 'rgba(0, 255, 102, 0.08)',
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 24,
  },
  stepTitle: {
    color: '#FFF',
    fontSize: 22,
    fontWeight: '800',
    textAlign: 'center',
    marginBottom: 14,
    lineHeight: 28,
  },
  stepDesc: {
    color: COLORS.textSecondary,
    fontSize: 14,
    textAlign: 'center',
    lineHeight: 22,
  },
  cardIllustration: {
    width: '100%',
    height: 50,
    backgroundColor: 'rgba(255,255,255,0.02)',
    borderColor: 'rgba(255,255,255,0.05)',
    borderWidth: 1,
    borderRadius: 12,
    marginTop: 24,
    justifyContent: 'center',
    alignItems: 'center',
  },
  illustrationOverlay: {
    position: 'absolute',
    left: 0,
    width: 6,
    height: '100%',
    backgroundColor: COLORS.primary,
    borderTopLeftRadius: 12,
    borderBottomLeftRadius: 12,
  },
  illustrationText: {
    color: 'rgba(255,255,255,0.3)',
    fontSize: 10,
    fontWeight: '900',
    letterSpacing: 2,
  },
  stepperContainer: {
    flexDirection: 'row',
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 30,
  },
  dot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: 'rgba(255, 255, 255, 0.15)',
    marginHorizontal: 5,
  },
  activeDot: {
    width: 24,
    backgroundColor: COLORS.primary,
  },
  actionBtn: {
    backgroundColor: COLORS.primary,
    height: 56,
    borderRadius: 16,
    justifyContent: 'center',
    alignItems: 'center',
    shadowColor: COLORS.primary,
    shadowOffset: { width: 0, height: 8 },
    shadowOpacity: 0.35,
    shadowRadius: 16,
    elevation: 6,
  },
  actionBtnText: {
    color: '#000',
    fontSize: 15,
    fontWeight: '900',
    letterSpacing: 2,
  }
});
