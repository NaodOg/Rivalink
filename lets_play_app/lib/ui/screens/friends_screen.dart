import 'package:flutter/material.dart';

import '../../core/data/repositories/app_repository.dart';
import '../../core/state/session_controller.dart';
import '../../core/theme/rivalink_theme.dart';
import '../widgets/pf_avatar.dart';
import '../widgets/pf_card.dart';
import '../widgets/pf_empty_state.dart';
import '../widgets/pf_segmented.dart';
import '../widgets/pf_skeleton.dart';

class FriendsScreen extends StatefulWidget {
  final SessionController session;
  final AppRepository repo;
  const FriendsScreen({super.key, required this.session, required this.repo});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  int _tab = 0;
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;

  static const _tabs = ['Following', 'Followers', 'Teammates'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = widget.session.token;
    if (token == null) return;
    setState(() => _loading = true);
    final List<dynamic> data;
    switch (_tab) {
      case 0:
        data = await widget.repo.getFollowing(token);
        break;
      case 1:
        data = await widget.repo.getFollowers(token);
        break;
      default:
        data = await widget.repo.getTeammates(token);
    }
    if (!mounted) return;
    setState(() {
      _users = data.cast<Map<String, dynamic>>();
      _loading = false;
    });
  }

  Future<void> _toggle(Map<String, dynamic> u) async {
    final token = widget.session.token;
    if (token == null) return;
    final following = await widget.repo.toggleFollow(token, u['user_id'] as int);
    if (!mounted) return;
    setState(() => u['is_following'] = following);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PFColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Friends'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: PFSegmented(
              labels: _tabs,
              index: _tab,
              onChanged: (i) {
                setState(() => _tab = i);
                _load();
              },
            ),
          ),
          const SizedBox(height: PFSpacing.md),
          Expanded(
            child: _loading
                ? ListView(
                    padding: const EdgeInsets.all(20),
                    children: const [
                      PFSkeletonCard(height: 68),
                      SizedBox(height: PFSpacing.sm),
                      PFSkeletonCard(height: 68),
                    ],
                  )
                : _users.isEmpty
                    ? ListView(children: [
                        const SizedBox(height: 40),
                        PFEmptyState(
                          icon: Icons.groups_outlined,
                          title: _tab == 2 ? 'No teammates yet' : 'Nobody here yet',
                          message: _tab == 2
                              ? 'Play a match or join a team to find people.'
                              : 'Follow players to build your circle.',
                        ),
                      ])
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        itemCount: _users.length,
                        separatorBuilder: (_, __) => const SizedBox(height: PFSpacing.sm),
                        itemBuilder: (_, i) => _row(_users[i]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _row(Map<String, dynamic> u) {
    final following = u['is_following'] == true;
    return PFCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          PFAvatar(name: u['name']?.toString(), imageUrl: u['profile_image']?.toString(), size: 40),
          const SizedBox(width: PFSpacing.md),
          Expanded(
            child: Text(u['name']?.toString() ?? 'Player',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall),
          ),
          _FollowButton(following: following, onTap: () => _toggle(u)),
        ],
      ),
    );
  }
}

class _FollowButton extends StatelessWidget {
  final bool following;
  final VoidCallback onTap;
  const _FollowButton({required this.following, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: following
          ? OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              child: const Text('Following'),
            )
          : FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: const Text('Follow'),
            ),
    );
  }
}
