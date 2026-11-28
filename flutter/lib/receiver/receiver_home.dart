// The receiver's home window: the app on a supported computer opens on
// exactly three things, Get help, Messages and My tickets (receiver plan,
// step 4). No settings, no address book, no connections to other
// computers, no ID or password.

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_hbb/models/nd_chat_model.dart';
import 'package:flutter_hbb/onboarding/onboarding_service.dart';

import 'get_help_view.dart';
import 'tickets_model.dart';
import 'tickets_view.dart';

enum ReceiverArea { help, messages, tickets }

/// Which area the home window shows, and which ticket to open: the tray's
/// entries and the notifications ask for them with a link.
class ReceiverRouter extends ChangeNotifier {
  ReceiverRouter([this.area = ReceiverArea.help]);

  ReceiverArea area;

  /// A ticket to open once My tickets shows; taken by the home window.
  int? ticket;

  void go(ReceiverArea to) {
    area = to;
    notifyListeners();
  }

  /// Opens the page of a link's path: "help", "chat" or "messages",
  /// "tickets" or "tickets/<id>". False for anything else (the window only
  /// comes to the front).
  bool open(String link) {
    final parts =
        link.split('/').where((p) => p.isNotEmpty).toList(growable: false);
    if (parts.isEmpty) return false;
    switch (parts.first) {
      case 'help':
        area = ReceiverArea.help;
        break;
      case 'chat':
      case 'messages':
        area = ReceiverArea.messages;
        break;
      case 'tickets':
        area = ReceiverArea.tickets;
        ticket = parts.length > 1 ? int.tryParse(parts[1]) : null;
        break;
      default:
        return false;
    }
    notifyListeners();
    return true;
  }
}

class ReceiverHome extends StatefulWidget {
  const ReceiverHome({
    super.key,
    required this.router,
    required this.onboarding,
    required this.chat,
    required this.messages,
    required this.tickets,
    required this.ticketActions,
    this.company = '',
  });

  final ReceiverRouter router;

  /// Get help starts quick support with the code through it.
  final OnboardingService onboarding;

  /// The chat with support, for the count of new messages.
  final NdChatModel chat;

  /// The Messages page (the chat page of nd_chat_page.dart).
  final WidgetBuilder messages;
  final NdTicketsModel tickets;
  final NdTicketActions ticketActions;

  /// The company's name from the server's branding, empty without one.
  final String company;

  @override
  State<ReceiverHome> createState() => _ReceiverHomeState();
}

class _ReceiverHomeState extends State<ReceiverHome> {
  @override
  void initState() {
    super.initState();
    widget.router.addListener(_routed);
    widget.chat.addListener(_changed);
    widget.tickets.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) => _routed());
  }

  @override
  void dispose() {
    widget.router.removeListener(_routed);
    widget.chat.removeListener(_changed);
    widget.tickets.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _routed() {
    if (!mounted) return;
    final r = widget.router;
    final id = r.ticket;
    if (r.area == ReceiverArea.tickets && id != null) {
      r.ticket = null;
      widget.tickets.openTicket(id);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
    final area = widget.router.area;
    final Widget page;
    switch (area) {
      case ReceiverArea.help:
        page = GetHelpView(
          key: const ValueKey('rcv-help'),
          service: widget.onboarding,
          company: widget.company,
          onMessages: () => widget.router.go(ReceiverArea.messages),
        );
        break;
      case ReceiverArea.messages:
        page = KeyedSubtree(
            key: const ValueKey('rcv-messages'),
            child: widget.messages(context));
        break;
      case ReceiverArea.tickets:
        page = TicketsView(
          key: const ValueKey('rcv-tickets'),
          model: widget.tickets,
          actions: widget.ticketActions,
        );
        break;
    }
    return ColoredBox(
      color: c.bg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 224,
            child: DecoratedBox(
              decoration: BoxDecoration(
                  color: c.bgSubtle,
                  border: Border(right: BorderSide(color: c.rule))),
              child: _Nav(
                area: area,
                messagesNew: widget.chat.unread,
                ticketsNew: widget.tickets.unread,
                onGo: widget.router.go,
              ),
            ),
          ),
          Expanded(child: page),
        ],
      ),
    );
  }
}

class _Nav extends StatelessWidget {
  const _Nav({
    required this.area,
    required this.messagesNew,
    required this.ticketsNew,
    required this.onGo,
  });

  final ReceiverArea area;
  final int messagesNew;
  final int ticketsNew;
  final ValueChanged<ReceiverArea> onGo;

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _NavItem(
                key: const ValueKey('rcv-nav-help'),
                icon: NdIcons.help,
                label: tr('nd-rcv-nav-help'),
                selected: area == ReceiverArea.help,
                onPressed: () => onGo(ReceiverArea.help),
              ),
              const SizedBox(height: 4),
              _NavItem(
                key: const ValueKey('rcv-nav-messages'),
                icon: NdIcons.chat,
                label: tr('nd-rcv-nav-messages'),
                count: messagesNew,
                selected: area == ReceiverArea.messages,
                onPressed: () => onGo(ReceiverArea.messages),
              ),
              const SizedBox(height: 4),
              _NavItem(
                key: const ValueKey('rcv-nav-tickets'),
                icon: NdIcons.article,
                label: tr('nd-rcv-nav-tickets'),
                count: ticketsNew,
                selected: area == ReceiverArea.tickets,
                onPressed: () => onGo(ReceiverArea.tickets),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
    this.count = 0,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
    final t = context.ndText;
    final news = count > 0 ? tr('nd-chat-new', ['$count']) : null;
    return NdPressable(
      onPressed: onPressed,
      label: news == null ? label : '$label, $news',
      selected: selected,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? c.bg : null,
          borderRadius: NdSize.r,
          border: Border.all(color: selected ? c.border : Colors.transparent),
        ),
        child: Row(children: [
          Icon(icon, size: 20, color: selected ? c.accent : c.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: t.label.copyWith(
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: c.text)),
          ),
          if (news != null)
            Text(news,
                key: ValueKey('rcv-nav-new-$label'),
                style: t.small
                    .copyWith(color: c.accent, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}
