import { initializeApp, getApps, getApp } from 'firebase/app';
import { initializeAuth, getReactNativePersistence } from 'firebase/auth';
import { initializeFirestore, persistentLocalCache, persistentMultipleTabManager } from 'firebase/firestore';
import { getStorage } from 'firebase/storage';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { Platform } from 'react-native';

const firebaseConfig = {
  apiKey: "AIzaSyA5LwTqkq-eVnGGIscB_uHYdo0QQARLh2Q",
  authDomain: "grye-52952.firebaseapp.com",
  projectId: "grye-52952",
  storageBucket: "grye-52952.firebasestorage.app",
  messagingSenderId: "609478884549",
  appId: "1:609478884549:web:fca36f4fb00f3fceeec4ac",
  measurementId: "G-6P3Q7WY4XD"
};

// Initialize Firebase App
const app = getApps().length === 0 ? initializeApp(firebaseConfig) : getApp();

// Initialize Auth with cross-platform persistence support
let auth;
if (Platform.OS === 'web') {
  const { getAuth } = require('firebase/auth');
  auth = getAuth(app);
} else {
  // Mobile persistence using AsyncStorage
  auth = initializeAuth(app, {
    persistence: getReactNativePersistence(AsyncStorage),
  });
}

// Initialize Firestore with local caching for offline durability and rapid loads
const db = initializeFirestore(app, {
  localCache: Platform.OS === 'web'
    ? undefined // Multi-tab caching has specific config in modern Firestore, default to standard cache for web
    : persistentLocalCache({
        tabManager: persistentMultipleTabManager(),
      }),
});

// Initialize Storage
const storage = getStorage(app);

export { app, auth, db, storage };
