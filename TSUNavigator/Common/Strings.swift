import Foundation

enum S {
    enum aStar {
        static var aMarshrut: String { tr("A* — Маршрут", "A* — Route") }
        static var analiz: String { tr("Анализ", "Analysis") }
        static var barer: String { tr("Барьер", "Barrier") }
        static var finish: String { tr("Финиш", "Finish") }
        static var gazon: String { tr("Газон", "Grass") }
        static var marshrut: String { tr("Маршрут", "Route") }
        static var mojaPozicijaStart: String { tr("Моя позиция — СТАРТ", "My location — START") }
        static var najtiPut: String { tr("Найти путь", "Find path") }
        static var nazhmiNajtiPut: String { tr("Нажми «Найти путь»", "Tap «Find path»") }
        static var otmena: String { tr("Отмена", "Cancel") }
        static var poGazonuMozhno: String { tr("По газону: можно", "Grass: allowed") }
        static var poGazonuNelzja: String { tr("По газону: нельзя", "Grass: forbidden") }
        static var podtverditZdanie: String { tr("Подтвердить здание", "Confirm building") }
        static var prolozhitMarshrut: String { tr("Проложить маршрут", "Build route") }
        static var prosmotreno: String { tr("Просмотрено", "Visited") }
        static var putNeNajden: String { tr("Путь не найден", "No path found") }
        static var skrytSpisokZavedenij: String { tr("Скрыть список заведений", "Hide place list") }
        static var start: String { tr("Старт", "Start") }
        static var tapniNaKartuIliZdanieFinish: String { tr("Тапни на карту или здание — ФИНИШ", "Tap on map or building — FINISH") }
        static var tapniNaKartuIliZdanieStart: String { tr("Тапни на карту или здание — СТАРТ", "Tap on map or building — START") }
        static var tapniteVPustoeMestoChtobyVyjti: String { tr("Тапните в пустое место, чтобы выйти из режима заведения", "Tap empty space to exit place mode") }
        static var zazhmiIVodiPalcemRisujStiraj: String { tr("Зажми и води пальцем — рисуй/стирай барьеры", "Hold and drag — draw/erase barriers") }
        static var zdanie: String { tr("Здание", "Building") }
    }

    enum ant {
        static var dlina: String { tr("Длина", "Length") }
        static var dostoprimechatelnostiDolzhnyBytPrivjazanyKKorpus: String { tr("Достопримечательности должны быть привязаны к корпусу на карте.", "Landmarks must be linked to a building on the map.") }
        static var gruppa: String { tr("Группа", "Group") }
        static var iteracii: String { tr("Итерации", "Iterations") }
        static var kovorking: String { tr("Коворкинг", "Coworking") }
        static var kovorkingiDolzhnyBytPrivjazanyKKorpusam: String { tr("Коворкинги должны быть привязаны к корпусам на карте.", "Coworkings must be linked to buildings on the map.") }
        static var marshrutNajden: String { tr("Маршрут найден", "Route found") }
        static var marshrutPoUniversitetskojRoshe: String { tr("Маршрут по университетской роще", "Route through university grove") }
        static var muravi: String { tr("Муравьи", "Ants") }
        static var muravinyjAlgoritm: String { tr("Муравьиный алгоритм...", "Ant colony algorithm...") }
        static var nazad: String { tr("Назад", "Back") }
        static var nazhmiteNaKartuChtobyUkazatGde: String { tr("Нажмите на карту, чтобы указать, где вы находитесь", "Tap the map to mark where you are") }
        static var nazhmiteNaKartuGdeSejchasNahoditsja: String { tr("Нажмите на карту — где сейчас находится группа", "Tap the map — where the group is now") }
        static var netDostoprimechatelnostej: String { tr("Нет достопримечательностей", "No landmarks") }
        static var netKovorkingov: String { tr("Нет коворкингов", "No coworkings") }
        static var ochistit: String { tr("Очистить", "Clear") }
        static var parametryMuravinogoAlgoritma: String { tr("Параметры муравьиного алгоритма", "Ant algorithm parameters") }
        static var perepolnenie: String { tr("Переполнение", "Overflow") }
        static var porjadokObhoda: String { tr("Порядок обхода:", "Visit order:") }
        static var postroitMarshrut: String { tr("Построить маршрут", "Build route") }
        static var progulka: String { tr("Прогулка", "Walk") }
        static var prokladkaDorogA: String { tr("Прокладка дорог A*...", "Building A* paths...") }
        static var raspredelenie: String { tr("Распределение:", "Distribution:") }
        static var raspredelenieGotovo: String { tr("Распределение готово", "Distribution ready") }
        static var raspredelitStudentov: String { tr("Распределить студентов", "Distribute students") }
        static var razmesheno: String { tr("Размещено", "Placed") }
        static var rezhim: String { tr("Режим", "Mode") }
        static var sbrosit: String { tr("Сбросить", "Reset") }
        static var startVybranNazhmitePostroitMarshrut: String { tr("Старт выбран — нажмите «Построить маршрут»", "Start selected — tap «Build route»") }
        static var tochek: String { tr("Точек", "Points") }
        static var tochkaStudentovVybrana: String { tr("Точка студентов выбрана", "Students point selected") }
        static var ukazatStartovujuTochku: String { tr("Указать стартовую точку", "Set start point") }
        static var vremja: String { tr("Время", "Time") }
        static var vyZdes: String { tr("Вы здесь", "You are here") }
        static var vyberiteDostoprimechatelnostiDljaObhoda: String { tr("Выберите достопримечательности для обхода", "Select landmarks to visit") }
        static var vyberiteHotjaByOdnuDostoprimechatelnost: String { tr("Выберите хотя бы одну достопримечательность", "Select at least one landmark") }
        static var zapusk: String { tr("Запуск...", "Running...") }
    }

    enum clustering {
        static var evklidovo: String { tr("Евклидово", "Euclidean") }
        static var klasterizacija: String { tr("Кластеризация", "Clustering") }
        static var konfliktnyeTochkiObvedenyPunktiromNaKarte: String { tr("Конфликтные точки обведены пунктиром на карте", "Conflicting points are outlined with a dashed line on the map") }
        static var manhetten: String { tr("Манхэттен", "Manhattan") }
        static var nazhimajteNaKartuChtobyRasstavitTochki: String { tr("Нажимайте на карту, чтобы расставить точки", "Tap the map to place points") }
        static var obeMetrikiDaliOdinakovyjRezultat: String { tr("Обе метрики дали одинаковый результат!", "Both metrics gave the same result!") }
        static var sravnitMetriki: String { tr("Сравнить метрики", "Compare metrics") }
    }

    enum content {
        static var kafe: String { tr("Кафе", "Cafe") }
        static var marshrut: String { tr("Маршрут", "Route") }
        static var mesta: String { tr("Места", "Places") }
        static var muravi: String { tr("Муравьи", "Ants") }
        static var nejroset: String { tr("Нейросеть", "Neural net") }
        static var obed: String { tr("Обед", "Lunch") }
        static var sovetnik: String { tr("Советник", "Advisor") }
    }

    enum decisionTree {
        static var bazovajaVyborkaTolkoChtenie: String { tr("Базовая выборка (только чтение)", "Base dataset (read-only)") }
        static var busStopLowShortCoffeeLow: String { tr("bus_stop,low,short,coffee,low,good,Буфет №1", "bus_stop,low,short,coffee,low,good,Buffet №1") }
        static var dannye: String { tr("Данные", "Data") }
        static var derevo: String { tr("Дерево", "Tree") }
        static var dobavitNovyeZapisi: String { tr("Добавить новые записи", "Add new records") }
        static var glubina: String { tr("Глубина", "Depth") }
        static var kolonkiLocationBudgetTimeAvailableFood: String { tr("Колонки: location, budget, time_available, food_type, queue_tolerance, weather, recommended_place (заголовок не нужен — берётся из базовой выборки)", "Columns: location, budget, time_available, food_type, queue_tolerance, weather, recommended_place (no header — taken from base dataset)") }
        static var list: String { tr("Лист", "Leaf") }
        static var listev: String { tr("Листьев", "Leaves") }
        static var maksGlubina: String { tr("Макс. глубина", "Max depth") }
        static var minIgDljaSohranenija: String { tr("Мин. IG для сохранения", "Min IG to keep") }
        static var minIgDljaVetvlenija: String { tr("Мин. IG для ветвления", "Min IG to split") }
        static var minObrazcovVListe: String { tr("Мин. образцов в листе", "Min samples per leaf") }
        static var nekotoryeOtvetyNeVstrechalisVObuchajushej: String { tr("Некоторые ответы не встречались в обучающей выборке — прошли через наиболее вероятную ветку.", "Some answers were absent in the training set — went through the most probable branch.") }
        static var netDannyh: String { tr("Нет данных", "No data") }
        static var netDereva: String { tr("Нет дерева", "No tree") }
        static var ochistit: String { tr("Очистить", "Clear") }
        static var opredelitZavedenie: String { tr("Определить заведение", "Identify place") }
        static var optimizacijaRazmeraPostObrezka: String { tr("Оптимизация размера (пост-обрезка)", "Size optimization (post-pruning)") }
        static var parametryPostroenija: String { tr("Параметры построения", "Build parameters") }
        static var perejditeNaVkladkuDannyeChtobyDobavit: String { tr("Перейдите на вкладку «Данные», чтобы добавить записи и перестроить дерево.", "Switch to the «Data» tab to add records and rebuild the tree.") }
        static var perejditeNaVkladkuDannyeIDobavte: String { tr("Перейдите на вкладку «Данные» и добавьте записи.", "Switch to the «Data» tab and add records.") }
        static var perestroitDerevo: String { tr("Перестроить дерево", "Rebuild tree") }
        static var primenit: String { tr("Применить", "Apply") }
        static var putPoDerevu: String { tr("Путь по дереву:", "Tree path:") }
        static var rekomenduetsja: String { tr("Рекомендуется:", "Recommended:") }
        static var slivatIzbytochnyeVetki: String { tr("Сливать избыточные ветки", "Merge redundant branches") }
        static var sovetnik: String { tr("Советник", "Advisor") }
        static var svernutParametry: String { tr("Свернуть параметры", "Collapse parameters") }
        static var tochnost: String { tr("Точность", "Accuracy") }
        static var uzlov: String { tr("Узлов", "Nodes") }
        static var vstavit: String { tr("Вставить", "Paste") }
        static var zapros: String { tr("Запрос", "Query") }
    }

    enum genetic {
        static var bljuda: String { tr("Блюда", "Dishes") }
        static var chtoVyHotite: String { tr("Что вы хотите?", "What do you want?") }
        static var geneticheskijAlgoritm: String { tr("Генетический алгоритм...", "Genetic algorithm...") }
        static var kruglosutochno: String { tr("круглосуточно", "24/7") }
        static var marshrutNajden: String { tr("Маршрут найден", "Route found") }
        static var marshrutZaObedom: String { tr("Маршрут за обедом", "Lunch route") }
        static var mest: String { tr("Мест", "Places") }
        static var nazad: String { tr("Назад", "Back") }
        static var nazhmiteNaKartuChtobyUkazatGde: String { tr("Нажмите на карту, чтобы указать, где вы находитесь", "Tap the map to mark where you are") }
        static var netPrivjazannyhZavedenij: String { tr("Нет привязанных заведений", "No linked places") }
        static var parametryAlgoritma: String { tr("Параметры алгоритма", "Algorithm parameters") }
        static var perejditeVoVkladkuEdaIPrivjazhite: String { tr("Перейдите во вкладку «Еда» и привяжите заведения к зданиям на карте.", "Switch to the «Food» tab and link places to buildings on the map.") }
        static var pokolenija: String { tr("Поколения", "Generations") }
        static var populjacija: String { tr("Популяция", "Population") }
        static var porjadokObhoda: String { tr("Порядок обхода:", "Visit order:") }
        static var postroitMarshrut: String { tr("Построить маршрут", "Build route") }
        static var prokladkaDorogA: String { tr("Прокладка дорог A*...", "Building A* paths...") }
        static var put: String { tr("Путь", "Path") }
        static var sbrosit: String { tr("Сбросить", "Reset") }
        static var startVybranNazhmitePostroitMarshrut: String { tr("Старт выбран — нажмите «Построить маршрут»", "Start selected — tap «Build route»") }
        static var vremja: String { tr("Время", "Time") }
        static var vyZdes: String { tr("Вы здесь", "You are here") }
        static var vyberiteBljudaKotoryeHotitePriobresti: String { tr("Выберите блюда, которые хотите приобрести", "Select the dishes you want to buy") }
        static var vybratStartovujuTochku: String { tr("Выбрать стартовую точку", "Select start point") }
        static var zapusk: String { tr("Запуск...", "Running...") }
    }

    enum neuralNet {
        static var komuStavimOcenku: String { tr("Кому ставим оценку", "Rating for") }
        static var nachniteRisovatCifruRezultatPojavitsjaAvtomatich: String { tr("Начните рисовать цифру, результат появится автоматически.", "Start drawing a digit — the result will appear automatically.") }
        static var narisujteOdnuCifruKrupnoIPo: String { tr("Нарисуйте одну цифру крупно и по центру.", "Draw a single digit — large and centered.") }
        static var nejronnajaSet: String { tr("Нейронная сеть", "Neural network") }
        static var netOcenok: String { tr("Нет оценок", "No ratings") }
        static var postavitOcenku: String { tr("Поставить оценку", "Submit rating") }
        static var vvediteOcenku: String { tr("Введите оценку", "Enter rating") }
        static var vyberiteZavedenie: String { tr("Выберите заведение", "Select a place") }
        static var zavedenie: String { tr("Заведение", "Place") }
    }

    enum placeCard {
        static var denisZmeev: String { tr("Денис Змеев", "Denis Zmeev") }
        static var dljaSbrosaVsehOcenokVvediteParol: String { tr("Для сброса всех оценок введите пароль.", "Enter the password to reset all ratings.") }
        static var etoMestoNePrivjazanoKKarte: String { tr("Это место не привязано к карте кампуса.", "This place is not linked to the campus map.") }
        static var ezhednevno: String { tr("Ежедневно", "Daily") }
        static var kruglosutochno: String { tr("Круглосуточно", "24/7") }
        static var menju: String { tr("Меню", "Menu") }
        static var nevernyjParol: String { tr("Неверный пароль.", "Wrong password.") }
        static var otkryto: String { tr("Открыто", "Open") }
        static var otmena: String { tr("Отмена", "Cancel") }
        static var parol: String { tr("Пароль", "Password") }
        static var poiskDostoprimechatelnosti: String { tr("Поиск достопримечательности", "Search landmark") }
        static var poiskKovorkinga: String { tr("Поиск коворкинга", "Search coworking") }
        static var poiskPoNazvanijuIliBljudu: String { tr("Поиск по названию или блюду", "Search by name or dish") }
        static var pokazatNaKarte: String { tr("Показать на карте", "Show on map") }
        static var postavitOcenku: String { tr("Поставить оценку", "Submit rating") }
        static var privjazatZdanie: String { tr("Привязать здание", "Link building") }
        static var razdel: String { tr("Раздел", "Section") }
        static var sbrosit: String { tr("Сбросить", "Reset") }
        static var sbrositOcenku: String { tr("Сбросить оценку", "Reset rating") }
        static var vse: String { tr("Все", "All") }
        static var zakryto: String { tr("Закрыто", "Closed") }
    }

    enum settings {
        static var jazyk: String { tr("Язык", "Language") }
        static var nastrojki: String { tr("Настройки", "Settings") }
    }
}
