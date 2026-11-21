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
flutter build apk --release --dart-define-from-file=config/google_tasks.json
```

Gotowy pakiet znajduje się w `build/app/outputs/flutter-apk/app-release.apk`. Lokalna kompilacja używa klucza deweloperskiego. Dystrybucja przez Google Play wymaga własnego klucza wydania.

## Domyślny kalendarz i Zadania Google

Dołączony APK ma wbudowany identyfikator klienta OAuth z pliku config/google_tasks.json. Google Tasks API, klienci Android i Web oraz zakres dostępu są skonfigurowane w projekcie My First Project (project-22e2e5bd-3a7c-48f9-bc1). Aplikacja jest w trybie testowym z kontem grzegorz.musial.1980@gmail.com dodanym jako użytkownik testowy. W aplikacji wybierz „Połącz konto Google”, aby nadać dostęp do zadań.

Kalendarz 5 min — Zadania Google

Domyślny kalendarz
W menu pod trzema kropkami wybierz „Domyślny kalendarz”, a następnie kalendarz do zapisywania nowych wydarzeń. Wybór jest pamiętany po zamknięciu aplikacji. Możesz jednorazowo wybrać inny kalendarz w formularzu nowego wydarzenia.

Wydarzenia i zadania
Przycisk „+” oraz dotknięcie osi czasu otwierają od razu formularz. Przełącznik „Wydarzenie / Zadanie” znajduje się u góry tego formularza i zachowuje wpisany tytuł podczas zmiany typu. Zadania są zapisywane na wybranej liście Google Tasks, tej samej, którą widzisz na https://tasks.google.com/. Widok zadań otworzysz również z menu „Zadania Google”. Widok pokazuje wszystkie zadania z wybranej listy. Nowe zadanie domyślnie otrzymuje datę wybraną w kalendarzu. Możesz zmienić lub usunąć datę.

Zadania Google wymagają osobnego połączenia z kontem Google. API Google Tasks udostępnia datę zadania i pomija godzinę. Zadania są wyświetlane na liście i można je oznaczyć jako wykonane.

Odtworzenie konfiguracji Google Cloud
1. Otwórz https://console.cloud.google.com/ i wybierz lub utwórz projekt.
2. Włącz Google Tasks API dla tego projektu.
   https://console.cloud.google.com/apis/library/tasks.googleapis.com
3. W Google Auth Platform skonfiguruj ekran zgody. Przy prywatnym użyciu wybierz odbiorców zewnętrznych i tryb testowy, a następnie dodaj swój adres Google do użytkowników testowych.
4. W sekcji Data Access dodaj zakres https://www.googleapis.com/auth/tasks.
5. W sekcji Clients utwórz klienta OAuth typu Android z danymi poniżej.
   Nazwa pakietu
   pl.grzegorzmusial.kalendarz_5min
   SHA-1 certyfikatu APK dołączonego do tej wersji
   53:5B:48:CC:E2:FD:82:71:37:77:A4:7A:1C:1A:A4:81:CB:CE:70:32
6. W tym samym projekcie utwórz drugiego klienta OAuth typu „Aplikacja internetowa” (Web application). Skopiuj jego identyfikator klienta, kończący się na .apps.googleusercontent.com.
7. W aplikacji otwórz menu pod trzema kropkami → „Dostęp do Zadań Google”. Wklej identyfikator klienta webowego i zapisz.
8. Otwórz „Zadania Google”, wybierz „Połącz konto Google” i udziel dostępu do zadań.

Identyfikator klienta webowego jest publicznym identyfikatorem konfiguracji. Formularz wymaga tylko tego identyfikatora.
Zmiana wcześniej używanego identyfikatora wymaga zamknięcia i ponownego uruchomienia aplikacji.
Konfiguracja kalendarza systemowego i wybór domyślnego kalendarza działają od razu po przyznaniu dostępu do kalendarza.

Weryfikacja
Testy aplikacji sprawdzają domyślny kalendarz po ponownym otwarciu, jednorazowy wybór innego kalendarza, wycofanie niedostępnego kalendarza, żądania Google Tasks API, pobieranie kolejnych stron wyników i zmianę stanu wykonania.
Połączenie z rzeczywistym kontem Google wymaga wykonania powyższej konfiguracji i zalogowania w aplikacji.

Dokumentacja Google
https://pub.dev/packages/google_sign_in_android
https://developers.google.com/workspace/tasks/auth
https://developers.google.com/tasks/reference/rest/v1/tasks


## Przeciąganie wydarzeń

Przytrzymaj wydarzenie, aby je przesunąć. Uchwyty na początku i końcu zmieniają godzinę rozpoczęcia i zakończenia w krokach co 5 minut. Oś przewija się automatycznie przy krawędziach ekranu. Zapis odświeża wydarzenia z zachowaniem dnia i pozycji przewinięcia.
