module DailyVerse

import NightlyNow.Holo.*

public class DailyVerseContact extends ContactHandler {

  private let dialog: wref<MessengerDialogViewController>;
  private let awaitingReply: Bool;

  private static func ReplyRequestId() -> Int32 = 1;
  private static func ReplyAmenId() -> Int32 = 2;
  private static func ReplyLabel() -> String = "Ask for a verse";
  private static func AmenLabel() -> String = "Amen";
  private static func RequestSentText() -> String = "Hit me";
  private static func FailureText() -> String = "Can't reach the archive right now, V. Try again in a bit.";
  private static func CooldownText() -> String = "Sit with the last one a while, V. I'll have another for you soon.";
  private static func EmptyText() -> String = "BibleAI is active. Ask any time, V.";

  private static func TypingTimeout() -> Float = 15.0;

  private func RenderReplies(messenger: wref<MessengerDialogViewController>) -> Void {
    messenger.ClearReplies();
    messenger.AddReply(DailyVerseContact.ReplyRequestId(), DailyVerseContact.ReplyLabel(), false, true, true);
    messenger.AddReply(DailyVerseContact.ReplyAmenId(), DailyVerseContact.AmenLabel(), false, false, true);
  }

  public func GetHash() -> Int32 = DailyVerseConst.ContactHash();

  public func AlwaysTop() -> Bool = false;

  public func IsMyThreadOpen() -> Bool {
    return IsDefined(this.dialog) && this.dialog.m_contactHash == this.GetHash();
  }

  public func CreateContactData(forMessages: Bool) -> ref<ContactData> {
    let data = new ContactData();
    data.hash = this.GetHash();
    data.localizedName = DailyVerseConst.ContactName();
    data.contactId = "DailyVerseContact";
    data.id = "DLYVRS";
    data.avatarID = t"PhoneAvatars.Avatar_Unknown";
    data.questRelated = false;
    data.isCallable = false;
    data.hasMessages = true;
    data.messagesCount = 1;
    data.playerIsLastSender = false;

    let system = DailyVerseSystem.GetInstance(GetGameInstance());
    let preview = IsDefined(system) ? system.GetLastVerse() : "";
    if StrLen(preview) == 0 {
      preview = "Grace and peace to you, V.";
    }

    if forMessages {
      data.type = MessengerContactType.SingleThread;
      data.lastMesssagePreview = preview;
      if this.HasPendingMessages() {
        data.unreadMessegeCount = 1;
        ArrayPush(data.unreadMessages, 0);
      }
    } else {
      data.type = MessengerContactType.Contact;
    }
    return data;
  }

  public func OnDialogOpen(messenger: wref<MessengerDialogViewController>) -> Bool {
    let system = DailyVerseSystem.GetInstance(GetGameInstance());
    if !IsDefined(system) {
      return false;
    }
    this.dialog = messenger;

    messenger.ClearMessages();
    messenger.ClearReplies();

    let verses = system.GetHistory();
    let count = ArraySize(verses);
    if count == 0 {
      messenger.AddMessage(DailyVerseContact.EmptyText(), MessageViewType.Received, DailyVerseConst.ContactName(), false);
    } else {
      let i = 0;
      while i < count {
        messenger.AddMessage(verses[i], MessageViewType.Received, DailyVerseConst.ContactName(), false);
        i += 1;
      }
    }

    if this.awaitingReply {

      messenger.AddMessage(DailyVerseContact.RequestSentText(), MessageViewType.Sent, "V", false);
      messenger.ShowTypingDots(DailyVerseConst.ContactName());
    } else {
      this.RenderReplies(messenger);
    }
    return true;
  }

  public func OnReplySelected(replyId: Int32) {
    if this.awaitingReply {
      return;
    }
    let system = DailyVerseSystem.GetInstance(GetGameInstance());
    if !IsDefined(system) {
      return;
    }

    if replyId == DailyVerseContact.ReplyAmenId() {
      if this.IsMyThreadOpen() {
        this.dialog.AddMessage(DailyVerseContact.AmenLabel(), MessageViewType.Sent, "V", true);
        this.dialog.ClearReplies();
      }
      return;
    }

    if replyId != DailyVerseContact.ReplyRequestId() {
      return;
    }

    if !system.CanRequestOnDemand() {
      if this.IsMyThreadOpen() {
        this.dialog.AddMessage(DailyVerseContact.RequestSentText(), MessageViewType.Sent, "V", true);
        this.dialog.AddMessage(DailyVerseContact.CooldownText(), MessageViewType.Received, DailyVerseConst.ContactName(), false);
        this.RenderReplies(this.dialog);
      }
      return;
    }

    this.awaitingReply = true;
    if this.IsMyThreadOpen() {
      this.dialog.AddMessage(DailyVerseContact.RequestSentText(), MessageViewType.Sent, "V", true);
      this.dialog.ClearReplies();
      this.dialog.ShowTypingDots(DailyVerseConst.ContactName());
    }

    this.QueueTypingDelay(GameInstance.GetDelaySystem(GetGameInstance()), DailyVerseContact.TypingTimeout(), replyId);

    system.ForceDeliver();
  }

  public func OnTypingFinished(replyId: Int32) {
    if this.awaitingReply {
      this.OnVerseFailed();
    }
  }

  public func OnVerseDelivered(verse: String) {
    let wasAwaiting = this.awaitingReply;
    this.awaitingReply = false;
    if !this.IsMyThreadOpen() {
      return;
    }
    if wasAwaiting {
      this.dialog.DVStopTypingDots();
    }
    this.dialog.AddMessage(verse, MessageViewType.Received, DailyVerseConst.ContactName(), true);
    this.RenderReplies(this.dialog);
  }

  public func OnVerseFailed() {
    if !this.awaitingReply {
      return;
    }
    this.awaitingReply = false;
    if this.IsMyThreadOpen() {
      this.dialog.DVStopTypingDots();
      this.dialog.AddMessage(DailyVerseContact.FailureText(), MessageViewType.Received, DailyVerseConst.ContactName(), false);
      this.RenderReplies(this.dialog);
    }
  }
}

@addMethod(MessengerDialogViewController)
public func DVStopTypingDots() -> Void {
  this.StopDotsAnimation();
}
