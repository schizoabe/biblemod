module DailyVerse

public abstract class DailyVerseConst {

  public static func ContactHash() -> Int32 = 1113678162;

  public static func ContactName() -> String = "BibleServiceAI";

  public static func PrimaryUrl() -> String = "https://bible-api.com/?random=verse";

  public static func FallbackUrl() -> String = "https://labs.bible.org/api/?passage=random&type=json";

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
