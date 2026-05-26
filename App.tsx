import React from 'react';
import { StatusBar } from 'react-native';
import { GreyReplicaScreen } from './src/screens/GreyReplicaScreen';

export default function App() {
  return (
    <>
      <StatusBar barStyle="dark-content" backgroundColor="#f5edf4" />
      <GreyReplicaScreen />
    </>
  );
}
