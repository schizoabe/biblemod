module DailyVerse

enum DailyVerseTranslation {
  WEB = 0,
  KJV = 1,
  ASV = 2,
  BBE = 3,
  WEBBE = 4,
}

public abstract class DailyVerseConst {

  public static func ContactHash() -> Int32 = 1113678162;

  public static func ContactName() -> String = "BibleServiceAI";

  public static func ApiRoot() -> String = "https://bible-api.com/data/";

  public static func FirstCheckDelay() -> Float = 25.0;

  public static func CheckInterval() -> Float = 180.0;

  public static func DeliveryHour() -> Int32 = 8;

  public static func MaxHistory() -> Int32 = 100;

  public static func OnDemandCooldown() -> Float = 1800.0;
}

public class DailyVerseSettings extends ScriptableSystem {
  @runtimeProperty("ModSettings.mod", "Daily Verse")
  @runtimeProperty("ModSettings.displayName", "Enabled")
  @runtimeProperty("ModSettings.description", "Text V a Bible verse each in-game day.")
  public let enabled: Bool = true;

  @runtimeProperty("ModSettings.mod", "Daily Verse")
  @runtimeProperty("ModSettings.displayName", "Translation")
  @runtimeProperty("ModSettings.description", "Which English translation verses are drawn from.")
  @runtimeProperty("ModSettings.displayValues.WEB", "World English Bible (modern)")
  @runtimeProperty("ModSettings.displayValues.KJV", "King James Version")
  @runtimeProperty("ModSettings.displayValues.ASV", "American Standard Version (1901)")
  @runtimeProperty("ModSettings.displayValues.BBE", "Bible in Basic English")
  @runtimeProperty("ModSettings.displayValues.WEBBE", "World English Bible (British)")
  public let translation: DailyVerseTranslation = DailyVerseTranslation.WEB;

  @runtimeProperty("ModSettings.mod", "Daily Verse")
  @runtimeProperty("ModSettings.displayName", "New Testament only")
  @runtimeProperty("ModSettings.description", "Draw verses only from the New Testament (Matthew through Revelation).")
  public let newTestamentOnly: Bool = false;

  @runtimeProperty("ModSettings.mod", "Daily Verse")
  @runtimeProperty("ModSettings.displayName", "Send a verse now")
  @runtimeProperty("ModSettings.description", "Flip this to fetch and deliver a verse immediately (for testing). It flips itself back.")
  public let forceNow: Bool = false;

  public static func Get(gi: GameInstance) -> ref<DailyVerseSettings> {
    return GameInstance.GetScriptableSystemsContainer(gi).Get(n"DailyVerse.DailyVerseSettings") as DailyVerseSettings;
  }

  public static func IsEnabled(gi: GameInstance) -> Bool {
    let self = DailyVerseSettings.Get(gi);
    return !IsDefined(self) || self.enabled;
  }

  public static func ScopeSuffix(gi: GameInstance) -> String {
    let self = DailyVerseSettings.Get(gi);
    if IsDefined(self) && self.newTestamentOnly {
      return "/NT";
    }
    return "";
  }

  public static func TranslationId(gi: GameInstance) -> String {
    let self = DailyVerseSettings.Get(gi);
    if !IsDefined(self) {
      return "web";
    }
    switch self.translation {
      case DailyVerseTranslation.KJV:
        return "kjv";
      case DailyVerseTranslation.ASV:
        return "asv";
      case DailyVerseTranslation.BBE:
        return "bbe";
      case DailyVerseTranslation.WEBBE:
        return "webbe";
    }
    return "web";
  }

  @if(ModuleExists("ModSettingsModule"))
  private func OnAttach() -> Void {
    ModSettings.RegisterListenerToClass(this);
    ModSettings.RegisterListenerToModifications(this);
  }

  @if(!ModuleExists("ModSettingsModule"))
  private func OnAttach() -> Void {}

  @if(ModuleExists("ModSettingsModule"))
  private func OnDetach() -> Void {
    ModSettings.UnregisterListenerToClass(this);
    ModSettings.UnregisterListenerToModifications(this);
  }

  @if(!ModuleExists("ModSettingsModule"))
  private func OnDetach() -> Void {}

  @if(ModuleExists("ModSettingsModule"))
  private func OnModSettingsChange() -> Void {
    if this.forceNow {
      this.forceNow = false;
      let system = DailyVerseSystem.GetInstance(GetGameInstance());
      if IsDefined(system) {
        system.ForceDeliver();
      }
    }
  }
}
