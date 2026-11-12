# Kalendarz 5 min

Kalendarz na Androida napisany we Flutterze. Widok dnia ma linie co 30 minut. Dotknij pustego miejsca na osi czasu, aby wybrać początek w kroku co 5 minut, albo użyj przycisku „+”. Nowe wydarzenie domyślnie trwa 5 minut. W edycji przycisk „Ustaw 5 min” skraca wydarzenie z zachowaniem jego godziny rozpoczęcia.

Nakładające się wydarzenia są wyświetlane w sąsiednich kolumnach. Przy wielu wydarzeniach o tej samej porze przesuń oś w poziomie, aby zobaczyć kolejne kolumny. Wydarzenia całodniowe są widoczne nad osią czasu. Edycja wydarzenia cyklicznego z regułą powtarzania dotyczy wybranego wystąpienia.

## Synchronizacja

1. Dodaj konto Google w ustawieniach Androida.
2. Włącz synchronizację Kalendarza dla tego konta i poczekaj na pierwsze pobranie wydarzeń.
3. Otwórz aplikację i przyznaj dostęp do kalendarza.

Aplikacja czyta i zapisuje wydarzenia w kalendarzach Google przez systemowy Android Calendar Provider. Android synchronizuje zmiany w obie strony zgodnie z ustawieniami konta i dostępnością sieci. Na urządzeniu można pracować na już zsynchronizowanych danych podczas pracy offline. Do dodawania i edycji potrzebny jest kalendarz z uprawnieniem zapisu.

## Uruchomienie projektu

Wymagania to Flutter 3.50 lub nowszy, Android SDK i urządzenie z Androidem albo emulator.

```powershell
flutter pub get
flutter analyze
flutter test
flutter run
flutter build apk --release
```

Gotowy pakiet znajduje się w `build/app/outputs/flutter-apk/app-release.apk`. Lokalna kompilacja używa klucza deweloperskiego. Dystrybucja przez Google Play wymaga własnego klucza wydania.
