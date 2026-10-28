class_name QuestLines
extends RefCounted
## Все реплики и подписи диалогов демо «За хлебом» и расширения «Ничего необычного» (EXT-01, часть L).
## Единственное место текстов: оригинальные черновики на согласование с правообладателем ШКЯ
## (docs/extension/DIALOGUES_AND_JOKES.md, «Редакторский контроль»). Слова «мобилизация» и «бусификация»
## здесь не звучат — смысл считывается вторым слоем (docs/extension/README.md).
##
## Цепочка — массив строк {speaker, text, portrait}: DialogPanel.open_chain() показывает их по одной,
## «ДАЛЬШЕ» (или E после допечатки) переключает, варианты ответа — только на последней.
## Портрет — id персонажа для DialogPanel.PORTRAIT_REGION (рисунок assets/art/characters/<id>_front_idle.svg).
##
## Счёт за миссию (не более 5–7 реплик, ACCEPTANCE_TESTS «UX / баланс»): Бабка-выдача, радио, полицейский,
## «военком», продавщица, Бабка-возврат, Бабка-сдача — семь; из них наблюдатели и радио — три.

const BABKA := "БАБКА"
const VENDOR := "ПРОДАВЩИЦА"
const ILYUSHA := "ИЛЮША"
const OFFICER := "ПОЛИЦЕЙСКИЙ"
## «Военком» (id account_officer): в игре — сотрудник вымышленной Городской службы уточнения маршрутов.
const ACCOUNT_OFFICER := "СОТРУДНИК ГСУМ"

# --- этап 1: выдача (ПРИНЯТЬ / ОТКАЗАТЬСЯ) ---
const OFFER := "Илюша, за хлебом сходи. И никуда не записывайся, у нас ручка дома"
const BUTTON_ACCEPT := "ПРИНЯТЬ"
const BUTTON_DECLINE := "ОТКАЗАТЬСЯ"

# --- Бабка без дела: до покупки — напоминание, после сдачи — прощание ---
const IDLE := "Хлеб не забудь, Илюша"
const IDLE_DONE := "Иди погрейся, Илюша"
const BUTTON_CLOSE := "ЗАКРЫТЬ"

# --- этап 2: радио при посадке в машину (субтитр, не блокирует управление) ---
const RADIO := "Радио: уважаемые жители, добровольные поездки стали ещё доступнее. Теперь даже без вашего обращения"
const RADIO_SECONDS := 6.0

# --- этап 5: полицейский у киоска (по E до обнаружения), выход свободный ---
const OFFICER_CHAIN := [
	{"speaker": OFFICER, "text": "Вы по какому вопросу?", "portrait": &"officer"},
	{"speaker": ILYUSHA, "text": "За хлебом", "portrait": &"ilyusha"},
	{"speaker": OFFICER, "text": "У нас тоже вопрос", "portrait": &"officer"},
]
const BUTTON_OFFICER_LEAVE := "ПОЙДУ Я"

# --- «военком» у автобуса (e01): два варианта ответа, итог один ---
const ACCOUNT_OFFICER_ASK := {"speaker": ACCOUNT_OFFICER, "text": "Вас подвезти?", "portrait": &"account_officer"}
const BUTTON_RIDE_NO := "НЕТ, СПАСИБО"
const BUTTON_RIDE_NEAR := "Я УЖЕ РЯДОМ"
const ACCOUNT_OFFICER_REPLY := {"speaker": ACCOUNT_OFFICER, "text": "Тем более надо подвезти", "portrait": &"account_officer"}
const BUTTON_RIDE_LEAVE := "Я ПЕШКОМ"

# --- этап 6: продавщица, первый подход — цепочка, покупка в конце ---
const VENDOR_CHAIN := [
	{"speaker": VENDOR, "text": "Батон один?", "portrait": &"vendor"},
	{"speaker": ILYUSHA, "text": "Один", "portrait": &"ilyusha"},
	{"speaker": VENDOR, "text": "А вас сколько?", "portrait": &"vendor"},
	{"speaker": ILYUSHA, "text": "Тоже один", "portrait": &"ilyusha"},
	{"speaker": VENDOR, "text": "Пока что", "portrait": &"vendor"},
]
## Повторный подход без покупки: короткая реплика, цепочка не повторяется (канон DEMO.md, раздел 5).
const VENDOR_AGAIN := "Батон? 35 рублей"
const BUTTON_BUY := "КУПИТЬ ХЛЕБ"
const BUTTON_LEAVE := "УЙТИ"

# --- этап 9: Бабка при возврате с хлебом, затем сдача ---
const RETURN_CHAIN := [
	{"speaker": BABKA, "text": "Ты где был?", "portrait": &"babka"},
	{"speaker": ILYUSHA, "text": "За хлебом", "portrait": &"ilyusha"},
	{"speaker": BABKA, "text": "А почему такой уставший?", "portrait": &"babka"},
	{"speaker": ILYUSHA, "text": "Там предложили отдохнуть", "portrait": &"ilyusha"},
]
const BUTTON_TURN_IN := "СДАТЬ ХЛЕБ"

# --- этап 10: сдача — два пузыря над Бабкой подряд, пауза между ними ---
const THANKS := "Ну всё, молодец. Завтра за молоком сходишь"
const THANKS_AFTER := "Или не сходишь"
const THANKS_PAUSE := 0.8

const BUTTON_NEXT := "ДАЛЬШЕ"
