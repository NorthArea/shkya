extends RefCounted
## Code-only visual metadata. Ratios preserve the previous front idle's visible height
## at every consumer's existing canvas height, without loading retired SVG resources.
## Native alpha bounds were measured at imported 1200px height before integration.
const VISIBLE_HEIGHT_RATIOS := {
	"ilyusha": 1090.0 / 1200.0,
	"babka": 1085.0 / 1200.0,
	"vendor": 1046.0 / 1200.0,
	"officer": 1144.0 / 1200.0,
	"resident_babka": 943.0 / 1200.0,
	"resident_man": 1102.0 / 1200.0,
	"resident_woman": 1039.0 / 1200.0,
	"resident_boy": 812.0 / 1200.0,
	"resident_shuba": 965.0 / 1200.0,
	"resident_beret": 1017.0 / 1200.0,
	"resident_violet": 944.0 / 1200.0,
	"resident_ushanka": 1095.0 / 1200.0,
	"resident_ushanka_walk": 1095.0 / 1200.0,
	"resident_tourist": 1078.0 / 1200.0,
	"resident_kid": 935.0 / 1200.0,
	"resident_kid2": 935.0 / 1200.0,
	"resident_dog": 1000.0 / 1200.0,
	"resident_kolpak": 1029.0 / 1200.0,
	"resident_bow": 953.0 / 1200.0,
	"resident_turban": 1039.0 / 1200.0,
	"police_long": 1056.0 / 1200.0,
	"police_round": 1048.0 / 1200.0,
	"guard_alt": 1066.0 / 1200.0,
	"police": 1054.0 / 1200.0,
	"guard": 1050.0 / 1200.0,
}
## NCD-RisC: estimated height at age 18 for Russia's 1996 birth cohort,
## rounded to metres. An art reference, not a current all-age population mean.
## https://ncdrisc.org/downloads/height/NCD_RisC_eLife_2016_height_age18_countries.csv
## https://elifesciences.org/articles/13410
const RF_ADULT_MALE_REFERENCE_M := 1.765
const RF_ADULT_FEMALE_REFERENCE_M := 1.653
const ILYUSHA_VISIBLE_HEIGHT_M := RF_ADULT_MALE_REFERENCE_M
const PORTRAIT_DIR := "res://assets/art/portraits3d/"
const PORTRAIT_KEYS: Array[StringName] = [&"babka", &"vendor", &"ilyusha", &"officer", &"account_officer"]

static func visible_height_ratio(drawing: String) -> float:
	assert(VISIBLE_HEIGHT_RATIOS.has(drawing), "Missing visual scale for " + drawing)
	return VISIBLE_HEIGHT_RATIOS.get(drawing, 1.0)

## CharacterSprite.height_m remains the legacy canvas height; 3D figures occupy
## only the original drawing's visible fraction of that canvas.
static func canvas_height_for(drawing: String, visible_height_m: float) -> float:
	return visible_height_m / visible_height_ratio(drawing)

static func resident_character(look: StringName) -> String:
	var drawing := "resident_%s" % look
	return drawing if VISIBLE_HEIGHT_RATIOS.has(drawing) else "vendor"

static func portrait_path(kind: StringName) -> String:
	return PORTRAIT_DIR + String(kind) + ".png" if kind in PORTRAIT_KEYS else ""
