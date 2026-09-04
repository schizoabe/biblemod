module DailyVerse

import RedHttpClient.*
import RedData.Json.*
import RedFileSystem.*
import NightlyNow.Holo.*

public class DailyVerseCheckCallback extends DelayCallback {
  public let system: wref<DailyVerseSystem>;

  public func Call() -> Void {
    if IsDefined(this.system) {
      this.system.RunDailyCheck();
    }
  }
}

public class DailyVerseSystem extends ScriptableSystem {

  private persistent let playthroughId: Int32;
  private persistent let lastDeliveredDay: Int32;
  private persistent let deliveredCount: Int32;

  private let history: array<String>;
  private let lastVerse: String;
  private let loaded: Bool;

  private let contact: ref<DailyVerseContact>;
  private let contactRegistered: Bool;
  private let phoneReady: Bool;
  private let pendingPush: Bool;
  private let triedFallback: Bool;
  private let forced: Bool;
  private let lastOnDemandStamp: Float;

  private func StateFileName() -> String {
    return "DailyVerse_" + IntToString(this.playthroughId) + ".txt";
  }

  private func EnsurePlaythroughId() -> Void {
    if this.playthroughId != 0 {
      return;
    }
    let id = RandRange(1, 2000000000);
    if id <= 0 {
      id = 1;
    }
    this.playthroughId = id;
    this.Log(s"new playthrough id \(id)");
  }

  public static func GetInstance(gi: GameInstance) -> ref<DailyVerseSystem> {
    return GameInstance.GetScriptableSystemsContainer(gi).Get(n"DailyVerse.DailyVerseSystem") as DailyVerseSystem;
  }

  private func OnAttach() -> Void {
    GameInstance.GetCallbackSystem()
      .RegisterCallback(n"Session/Ready", this, n"OnSessionReady")
      .SetLifetime(CallbackLifetime.Forever);
  }

  private func OnDetach() -> Void {
    GameInstance.GetCallbackSystem().UnregisterCallback(n"Session/Ready", this, n"OnSessionReady");
  }

  private cb func OnSessionReady(event: ref<GameSessionEvent>) -> Void {
    if event.IsPreGame() {
      return;
    }
    this.LoadState();
    this.EnsureContact();
    this.ScheduleCheck(DailyVerseConst.FirstCheckDelay());
  }

  private func LoadState() -> Void {
    if this.loaded {
      return;
    }
    this.loaded = true;
    this.EnsurePlaythroughId();

    let storage = FileSystem.GetSharedStorage();
    if IsDefined(storage) && Equals(storage.Exists(this.StateFileName()), FileSystemStatus.True) {
      let file = storage.GetFile(this.StateFileName());
      if IsDefined(file) {
        let lines = file.ReadAsLines();
        let i = 1;
        while i < ArraySize(lines) {
          if StrLen(lines[i]) > 0 {
            ArrayPush(this.history, lines[i]);
          }
          i += 1;
        }
      }
    }

    while ArraySize(this.history) > this.deliveredCount && this.deliveredCount >= 0 {
      ArrayErase(this.history, ArraySize(this.history) - 1);
    }
    this.deliveredCount = ArraySize(this.history);

    let n = ArraySize(this.history);
    this.lastVerse = n > 0 ? this.history[n - 1] : "";
    this.Log(s"loaded \(n) verse(s) for playthrough \(this.playthroughId), day marker \(this.lastDeliveredDay)");
  }

  private func SaveState() -> Void {
    let storage = FileSystem.GetSharedStorage();
    if !IsDefined(storage) {
      return;
    }
    let file = storage.GetFile(this.StateFileName());
    if !IsDefined(file) {
      return;
    }

    let lines: array<String>;
    ArrayPush(lines, IntToString(this.lastDeliveredDay));
    for verse in this.history {
      ArrayPush(lines, verse);
    }
    file.WriteLines(lines);
  }

  private func GetHoloSystem() -> ref<HoloSystem> {
    let player = GetPlayer(this.GetGameInstance());
    if !IsDefined(player) {
      return null;
    }
    return HoloSystem.Get(player);
  }

  private func EnsureContact() -> Void {
    if this.contactRegistered {
      return;
    }
    if !IsDefined(this.contact) {
      this.contact = new DailyVerseContact();
    }
    let holo = this.GetHoloSystem();
    if IsDefined(holo) {
      holo.AddContact(this.contact);
      this.contactRegistered = true;
    }
  }

  private func Log(msg: String) -> Void {
  }

  private func ScheduleCheck(delay: Float) -> Void {
    let cb = new DailyVerseCheckCallback();
    cb.system = this;
    GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(cb, delay, false);
  }

  private func GameStamp() -> Float {
    return GameInstance.GetTimeSystem(this.GetGameInstance()).GetGameTimeStamp();
  }

  private func CurrentDay() -> Int32 {
    return GameInstance.GetTimeSystem(this.GetGameInstance()).GetGameTime().Days();
  }

  private func CurrentHour() -> Int32 {
    return GameInstance.GetTimeSystem(this.GetGameInstance()).GetGameTime().Hours();
  }

  public func CanRequestOnDemand() -> Bool {
    return (this.GameStamp() - this.lastOnDemandStamp) >= DailyVerseConst.OnDemandCooldown();
  }

  public func RunDailyCheck() -> Void {

    this.ScheduleCheck(DailyVerseConst.CheckInterval());

    this.LoadState();
    this.EnsureContact();

    if this.pendingPush {
      this.TryDeliverPush();
    }

    if !DailyVerseSettings.IsEnabled(this.GetGameInstance()) {
      return;
    }

    let day = this.CurrentDay();
    let hour = this.CurrentHour();
    let firstEver = this.deliveredCount == 0;

    let due = (firstEver || day != this.lastDeliveredDay)
      && (firstEver || hour >= DailyVerseConst.DeliveryHour());
    this.Log(s"check: day=\(day) hour=\(hour) lastDeliveredDay=\(this.lastDeliveredDay) count=\(this.deliveredCount) due=\(due)");
    if due {
      this.Fetch(false);
    }
  }

  public func ForceDeliver() -> Void {
    this.Log("ForceDeliver requested");
    this.forced = true;
    this.lastOnDemandStamp = this.GameStamp();
    this.Fetch(false);
  }

  private func BuildUrl(useFallback: Bool) -> String {
    let gi = this.GetGameInstance();
    let id = DailyVerseSettings.TranslationId(gi);
    if useFallback {
      id = Equals(id, "web") ? "kjv" : "web";
    }
    return DailyVerseConst.ApiRoot() + id + "/random" + DailyVerseSettings.ScopeSuffix(gi);
  }

  private func Fetch(useFallback: Bool) -> Void {
    this.triedFallback = useFallback;
    let url = this.BuildUrl(useFallback);
    this.Log(s"GET \(url)");

    let headers: array<HttpHeader>;
    ArrayPush(headers, HttpHeader.Create("Accept", "application/json"));
    ArrayPush(headers, HttpHeader.Create("User-Agent", "CP2077-DailyVerse"));
    AsyncHttpClient.Get(HttpCallback.Create(this, n"OnVerseResponse"), url, headers);
  }

  private cb func OnVerseResponse(response: ref<HttpResponse>) -> Void {
    if !IsDefined(response) {
      this.Log("response is null");
      this.OnFetchFailed();
      return;
    }
    if !Equals(response.GetStatus(), HttpStatus.OK) {
      this.Log(s"HTTP \(response.GetStatusCode())");
      this.OnFetchFailed();
      return;
    }

    let verse = this.ParseVerse(response);
    if StrLen(verse) == 0 {
      this.Log(s"could not parse response (fallback=\(this.triedFallback)): \(response.GetText())");
      this.OnFetchFailed();
      return;
    }

    this.Deliver(verse);
  }

  private func OnFetchFailed() -> Void {
    if !this.triedFallback {
      this.Log("primary failed, trying fallback");
      this.Fetch(true);
      return;
    }
    this.forced = false;
    this.Log("fallback also failed - will retry on the next check");
    if IsDefined(this.contact) {
      this.contact.OnVerseFailed();
    }
  }

  private func ParseVerse(response: ref<HttpResponse>) -> String {
    let json = response.GetJson();
    if !IsDefined(json) || !json.IsObject() {
      return "";
    }
    let rv = (json as JsonObject).GetKey("random_verse") as JsonObject;
    if !IsDefined(rv) {
      return "";
    }

    let chapter = "";
    let verse = "";
    let cv = rv.GetKey("chapter");
    if IsDefined(cv) {
      chapter = cv.ToString();
    }
    let vv = rv.GetKey("verse");
    if IsDefined(vv) {
      verse = vv.ToString();
    }

    let reference = rv.GetKeyString("book") + " " + chapter + ":" + verse;
    return this.Compose(rv.GetKeyString("text"), reference);
  }

  private func Compose(rawText: String, rawReference: String) -> String {
    let text = this.Sanitize(rawText);
    let reference = this.Sanitize(rawReference);
    if StrLen(text) == 0 {
      return "";
    }
    if StrLen(reference) == 0 {
      return "\"" + text + "\"";
    }
    return "\"" + text + "\"  -  " + reference;
  }

  private func Sanitize(input: String) -> String {
    let s = input;
    s = StrReplaceAll(s, "\n", " ");
    s = StrReplaceAll(s, "\r", " ");
    s = StrReplaceAll(s, "<b>", "");
    s = StrReplaceAll(s, "</b>", "");
    s = StrReplaceAll(s, "<i>", "");
    s = StrReplaceAll(s, "</i>", "");
    s = StrReplaceAll(s, "&#8217;", "'");
    s = StrReplaceAll(s, "&#8216;", "'");
    s = StrReplaceAll(s, "&#8220;", "\"");
    s = StrReplaceAll(s, "&#8221;", "\"");
    s = StrReplaceAll(s, "&#8212;", "-");
    s = StrReplaceAll(s, "&#8211;", "-");
    s = StrReplaceAll(s, "&quot;", "\"");
    s = StrReplaceAll(s, "&amp;", "&");
    s = StrReplaceAll(s, "&nbsp;", " ");
    s = StrReplaceAll(s, "  ", " ");
    return s;
  }

  private func Deliver(verse: String) -> Void {
    let wasForced = this.forced;
    this.forced = false;

    let size = ArraySize(this.history);
    if !wasForced && size > 0 && Equals(this.history[size - 1], verse) {

      this.Log("duplicate of last verse, retrying next check");
      return;
    }

    ArrayPush(this.history, verse);
    while ArraySize(this.history) > DailyVerseConst.MaxHistory() {
      ArrayErase(this.history, 0);
    }
    this.lastVerse = verse;
    this.lastDeliveredDay = this.CurrentDay();
    this.deliveredCount = ArraySize(this.history);
    this.pendingPush = true;

    this.SaveState();
    this.Log(s"delivered (day \(this.lastDeliveredDay)): \(verse)");

    if IsDefined(this.contact) && this.contact.IsMyThreadOpen() {
      this.pendingPush = false;
    }
    this.TryDeliverPush();
    if IsDefined(this.contact) {
      this.contact.OnVerseDelivered(verse);
    }
  }

  private func TryDeliverPush() -> Void {
    if !this.pendingPush {
      return;
    }
    if !this.phoneReady {
      this.Log("push deferred - phone HUD not ready yet");
      return;
    }
    if !DailyVerseSettings.IsEnabled(this.GetGameInstance()) {
      return;
    }
    let holo = this.GetHoloSystem();
    if !IsDefined(holo) {
      this.Log("push deferred - HoloSystem not available");
      return;
    }
    this.EnsureContact();
    holo.SendPushNotification(DailyVerseConst.ContactHash(), DailyVerseConst.ContactName(), this.lastVerse);
    this.pendingPush = false;
    this.Log("push sent");
  }

  public func SetPhoneReady(ready: Bool) -> Void {
    this.phoneReady = ready;
  }

  public func GetHistory() -> array<String> {
    return this.history;
  }

  public func GetLastVerse() -> String {
    return this.lastVerse;
  }
}

@wrapMethod(NewHudPhoneGameController)
protected cb func OnInitialize() -> Bool {
  let result = wrappedMethod();
  let system = DailyVerseSystem.GetInstance(GetGameInstance());
  if IsDefined(system) {
    system.SetPhoneReady(true);
  }
  return result;
}

@wrapMethod(NewHudPhoneGameController)
protected cb func OnUninitialize() -> Bool {
  let result = wrappedMethod();
  let system = DailyVerseSystem.GetInstance(GetGameInstance());
  if IsDefined(system) {
    system.SetPhoneReady(false);
  }
  return result;
}
