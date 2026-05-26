import React from 'react';
import { View, Text, StyleSheet, FlatList, TouchableOpacity } from 'react-native';
import { COLORS } from '../theme/colors';
import { Transaction } from '../store/useAppStore';
import { ArrowUpRight, ArrowDownLeft, RefreshCw, CreditCard } from 'lucide-react';

interface TransactionListProps {
  transactions: Transaction[];
  onSelectTransaction?: (tx: Transaction) => void;
  limit?: number;
}

export const TransactionList: React.FC<TransactionListProps> = ({ transactions, onSelectTransaction, limit }) => {
  const getIcon = (type: Transaction['type'], isFrozen?: boolean) => {
    const size = 20;
    const color = '#FFF';
    switch (type) {
      case 'send':
        return <ArrowUpRight size={size} color={COLORS.danger} />;
      case 'receive':
        return <ArrowDownLeft size={size} color={COLORS.success} />;
      case 'exchange':
        return <RefreshCw size={size} color={COLORS.info} />;
      case 'card_payment':
        return <CreditCard size={size} color={COLORS.primary} />;
    }
  };

  const displayedTransactions = limit ? transactions.slice(0, limit) : transactions;

  if (transactions.length === 0) {
    return (
      <View style={styles.emptyContainer}>
        <Text style={styles.emptyText}>No transactions yet.</Text>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      {displayedTransactions.map((item) => {
        const isPositive = item.type === 'receive' || (item.type === 'exchange' && item.amount > 0);
        const symbol = isPositive ? '+' : '-';
        const formattedAmount = `${symbol}${item.currency} ${Math.abs(item.amount).toFixed(2)}`;
        
        // Parse date for clean view
        const dateObj = new Date(item.date);
        const formattedDate = dateObj.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });

        return (
          <TouchableOpacity
            key={item.id}
            activeOpacity={0.7}
            onPress={() => onSelectTransaction?.(item)}
            style={styles.txRow}
          >
            <View style={styles.leftCol}>
              <View style={styles.iconContainer}>
                {getIcon(item.type)}
              </View>
              <View style={styles.infoCol}>
                <Text style={styles.txTitle}>{item.title}</Text>
                <Text style={styles.txSubtitle}>{item.subtitle} • {formattedDate}</Text>
              </View>
            </View>

            <View style={styles.rightCol}>
              <Text style={[
                styles.amountText,
                isPositive ? styles.positiveText : styles.negativeText
              ]}>
                {formattedAmount}
              </Text>
              <View style={[
                styles.statusBadge,
                item.status === 'completed' ? styles.statusCompleted : styles.statusPending
              ]}>
                <Text style={styles.statusText}>{item.status.toUpperCase()}</Text>
              </View>
            </View>
          </TouchableOpacity>
        );
      })}
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    width: '100%',
  },
  txRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    backgroundColor: 'rgba(255, 255, 255, 0.02)',
    borderColor: 'rgba(255, 255, 255, 0.04)',
    borderWidth: 1,
    borderRadius: 16,
    padding: 16,
    marginBottom: 10,
  },
  leftCol: {
    flexDirection: 'row',
    alignItems: 'center',
    flex: 1,
  },
  iconContainer: {
    width: 44,
    height: 44,
    borderRadius: 14,
    backgroundColor: 'rgba(255, 255, 255, 0.05)',
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 14,
  },
  infoCol: {
    flex: 1,
    justifyContent: 'center',
  },
  txTitle: {
    color: '#FFF',
    fontSize: 14,
    fontWeight: '700',
  },
  txSubtitle: {
    color: COLORS.textSecondary,
    fontSize: 11,
    marginTop: 4,
  },
  rightCol: {
    alignItems: 'flex-end',
    marginLeft: 10,
  },
  amountText: {
    fontSize: 14,
    fontWeight: '800',
  },
  positiveText: {
    color: COLORS.primary,
  },
  negativeText: {
    color: '#FFF',
  },
  statusBadge: {
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: 4,
    marginTop: 6,
  },
  statusCompleted: {
    backgroundColor: 'rgba(16, 185, 129, 0.1)',
  },
  statusPending: {
    backgroundColor: 'rgba(245, 158, 11, 0.1)',
  },
  statusText: {
    fontSize: 8,
    fontWeight: '900',
    color: 'rgba(255, 255, 255, 0.6)',
    letterSpacing: 0.5,
  },
  emptyContainer: {
    padding: 40,
    justifyContent: 'center',
    alignItems: 'center',
  },
  emptyText: {
    color: COLORS.textSecondary,
    fontSize: 14,
  }
});
