// 单词页顶部的三张卡：今天这批、没学完的、到期复习的。
//
// 三张卡同一个底色，只靠左侧功能色和内容区分——之前一张灰一张粉、
// 还有一张淡蓝，换页时像进了三个 App。
// 文案只留数字和动作，不再解释规则。

import 'package:flutter/material.dart';

import '../models/word.dart';
import '../theme/module_palette.dart';
import 'fx.dart';
import 'motion_button.dart';

/// 卡片头：图标 + 标题 + 一行数据
class _CardHead extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color accent;

  const _CardHead({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final ModulePalette p = ModulePalette.of(context);
    return Row(
      children: <Widget>[
        Icon(icon, size: 18, color: accent),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: p.ink,
                ),
              ),
              if (subtitle != null && subtitle!.isNotEmpty) ...<Widget>[
                const SizedBox(height: 2),
                Text(subtitle!, style: TextStyle(fontSize: 11, color: p.muted)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 一排小号次要操作
class _MiniActions extends StatelessWidget {
  final List<_MiniAction> actions;

  const _MiniActions({required this.actions});

  @override
  Widget build(BuildContext context) {
    final ModulePalette p = ModulePalette.of(context);
    return Wrap(
      spacing: 2,
      children: actions
          .map(
            (_MiniAction a) => TextButton(
              onPressed: a.onTap,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 34),
                foregroundColor: p.muted,
              ),
              child: Text(a.label, style: const TextStyle(fontSize: 12)),
            ),
          )
          .toList(),
    );
  }
}

class _MiniAction {
  final String label;
  final VoidCallback onTap;

  const _MiniAction(this.label, this.onTap);
}

/// 今日抽词
class TodayCard extends StatelessWidget {
  final List<Word> today;
  final int drawable;
  final int dailyCount;
  final bool loop;
  final VoidCallback onStart;
  final VoidCallback onSwitchFlow;
  final VoidCallback onDrawMore;
  final VoidCallback onClear;
  final VoidCallback onImport;
  final VoidCallback onQuiz;

  const TodayCard({
    super.key,
    required this.today,
    required this.drawable,
    required this.dailyCount,
    required this.loop,
    required this.onStart,
    required this.onSwitchFlow,
    required this.onDrawMore,
    required this.onClear,
    required this.onImport,
    required this.onQuiz,
  });

  @override
  Widget build(BuildContext context) {
    final ModulePalette p = ModulePalette.of(context);
    final bool hasToday = today.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _CardHead(
              icon: hasToday ? Icons.today : Icons.shuffle,
              title: hasToday ? '今天的 ${today.length} 个词' : '今天还没抽词',
              subtitle: hasToday ? (loop ? '小循环' : '四步') : '$drawable 个未抽',
              accent: p.word,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: MotionButton(
                label: hasToday
                    ? '开始'
                    : (drawable > 0 ? '抽 $dailyCount 个' : '导入词表'),
                icon: hasToday
                    ? Icons.play_arrow
                    : (drawable > 0 ? Icons.shuffle : Icons.file_open_outlined),
                kind: MotionKind.flip,
                color: p.word,
                onPressed: hasToday
                    ? onStart
                    : (drawable > 0 ? onDrawMore : onImport),
              ),
            ),
            if (hasToday)
              _MiniActions(
                actions: <_MiniAction>[
                  _MiniAction(loop ? '换四步' : '换循环', onSwitchFlow),
                  _MiniAction('加抽', onDrawMore),
                  _MiniAction('快刷', onQuiz),
                  _MiniAction('清空', onClear),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// 抽过但没学完的
class UnfinishedCard extends StatelessWidget {
  final List<Word> words;
  final VoidCallback onContinue;
  final VoidCallback onQuiz;
  final VoidCallback onGiveUp;

  const UnfinishedCard({
    super.key,
    required this.words,
    required this.onContinue,
    required this.onQuiz,
    required this.onGiveUp,
  });

  @override
  Widget build(BuildContext context) {
    final ModulePalette p = ModulePalette.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _CardHead(
              icon: Icons.play_circle_outline,
              title: '还有 ${words.length} 个没学完',
              accent: p.chat,
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '之前抽的，和今天这批分开算',
                style: TextStyle(fontSize: 11, color: p.muted),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: MotionButton(
                label: '接着学',
                icon: Icons.play_arrow,
                kind: MotionKind.pulse,
                color: p.chat,
                onPressed: onContinue,
              ),
            ),
            _MiniActions(
              actions: <_MiniAction>[
                _MiniAction('快刷', onQuiz),
                _MiniAction('放弃', onGiveUp),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 到期该复习的旧词
class DueCard extends StatelessWidget {
  final List<Word> words;
  final VoidCallback onReview;
  final VoidCallback onQuiz;

  const DueCard({
    super.key,
    required this.words,
    required this.onReview,
    required this.onQuiz,
  });

  @override
  Widget build(BuildContext context) {
    final ModulePalette p = ModulePalette.of(context);
    final bool hasDue = words.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _CardHead(
              icon: hasDue ? Icons.history_edu : Icons.check_circle_outline,
              title: hasDue ? '该复习 ${words.length} 个' : '今天没有要复习的',
              accent: hasDue ? p.word : p.muted,
            ),
            if (hasDue) ...<Widget>[
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton(
                      onPressed: onReview,
                      style: FilledButton.styleFrom(
                        backgroundColor: p.word,
                        foregroundColor: ModulePalette.onAccent(p.word),
                      ),
                      child: const Text('复习'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onQuiz,
                      child: const Text('快刷'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 今日任务：把「补学 + 新词 + 到期」合成一个入口，减少自己拼数字。
class TodayTaskCard extends StatefulWidget {
  final int newCount;
  final int dueCount;
  final int catchUpCount;

  /// 受上限限制没排进来的数量
  final int moreCount;

  /// 每天抽多少新词、排多少复习/补学，点开卡片就能改
  final int dailyCount;
  final int reviewCap;
  final int catchUpCap;
  final ValueChanged<int> onDaily;
  final ValueChanged<int> onReview;
  final ValueChanged<int> onCatch;

  final VoidCallback onStart;
  final VoidCallback onAll;
  final VoidCallback onQuiz;
  final VoidCallback? onGiveUp;
  final VoidCallback? onMore;

  const TodayTaskCard({
    super.key,
    required this.newCount,
    required this.dueCount,
    required this.catchUpCount,
    required this.dailyCount,
    required this.reviewCap,
    required this.catchUpCap,
    required this.onDaily,
    required this.onReview,
    required this.onCatch,
    required this.onStart,
    required this.onAll,
    required this.onQuiz,
    this.onGiveUp,
    this.onMore,
    this.moreCount = 0,
  });

  @override
  State<TodayTaskCard> createState() => _TodayTaskCardState();
}

class _TodayTaskCardState extends State<TodayTaskCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final ModulePalette p = ModulePalette.of(context);
    final int newCount = widget.newCount;
    final int dueCount = widget.dueCount;
    final int catchUpCount = widget.catchUpCount;
    final int moreCount = widget.moreCount;
    final int total = newCount + dueCount + catchUpCount;
    final bool empty = total == 0;

    final List<String> parts = <String>[
      if (newCount > 0) '$newCount 新词',
      if (dueCount > 0) '$dueCount 复习',
      if (catchUpCount > 0) '$catchUpCount 补学',
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.line),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: p.ink.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _open = !_open),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      empty ? Icons.check_circle_outline : Icons.today_outlined,
                      size: 20,
                      color: empty ? p.muted : p.word,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      empty ? (moreCount > 0 ? '今天没排任务' : '今天的词清完了') : '今日任务',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: p.ink,
                      ),
                    ),
                    Icon(
                      _open ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: p.muted,
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                empty ? '' : '$total 个',
                style: TextStyle(fontSize: 11, color: p.muted),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            empty
                ? (moreCount > 0 ? '还有 $moreCount 个在等着，可以全部加入' : '想多背就再抽一组，别硬撑')
                : parts.join(' · '),
            style: TextStyle(fontSize: 13, color: p.muted),
          ),
          if (_open) ...<Widget>[
            const SizedBox(height: 8),
            _stepRow(p, '新词', widget.dailyCount, 1, 100, widget.onDaily),
            _stepRow(p, '复习', widget.reviewCap, 0, 200, widget.onReview),
            _stepRow(p, '补学', widget.catchUpCap, 0, 100, widget.onCatch),
            Text(
              '补学 = 之前抽到没学完的词；设为 0 就当天不排',
              style: TextStyle(fontSize: 11, color: p.muted),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              children: <Widget>[
                if (widget.onGiveUp != null && catchUpCount > 0)
                  TextButton(
                    onPressed: widget.onGiveUp,
                    child: const Text('放弃补学', style: TextStyle(fontSize: 12)),
                  ),
                if (moreCount > 0)
                  TextButton(
                    onPressed: widget.onAll,
                    child: Text(
                      '全部加入（$moreCount）',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                TextButton(
                  onPressed: widget.onQuiz,
                  child: const Text('快刷这一批', style: TextStyle(fontSize: 12)),
                ),
                TextButton(
                  onPressed: widget.onMore,
                  child: const Text('更多', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: empty
                        ? (moreCount > 0 ? widget.onAll : widget.onQuiz)
                        : widget.onStart,
                    icon: Icon(empty ? Icons.bolt : Icons.play_arrow, size: 19),
                    label: Text(
                      empty ? (moreCount > 0 ? '全部加入' : '再练一组') : '开始',
                      style: const TextStyle(fontSize: 15),
                    ),
                    style: FilledButton.styleFrom(
                      // 主操作压成深色，页面里不再有大块高饱和色
                      backgroundColor: p.ink,
                      foregroundColor: p.canvas,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepRow(
    ModulePalette p,
    String label,
    int value,
    int min,
    int max,
    ValueChanged<int> onChanged,
  ) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 32,
          child: Text(label, style: TextStyle(fontSize: 12, color: p.muted)),
        ),
        const Spacer(),
        IconButton(
          tooltip: '减少',
          visualDensity: VisualDensity.compact,
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: Icon(Icons.remove, size: 16, color: p.muted),
        ),
        SizedBox(
          width: 30,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: p.ink,
            ),
          ),
        ),
        IconButton(
          tooltip: '增加',
          visualDensity: VisualDensity.compact,
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: Icon(Icons.add, size: 16, color: p.muted),
        ),
      ],
    );
  }
}

/// 单词页最上面并排的两个模块：学习 / 复习。
class StudyReviewRow extends StatelessWidget {
  final int todayCount;
  final int drawable;
  final int dailyCount;
  final int dueCount;
  final bool loop;
  final VoidCallback onStudy;
  final VoidCallback onDraw;
  final VoidCallback onImport;
  final VoidCallback onReview;

  const StudyReviewRow({
    super.key,
    required this.todayCount,
    required this.drawable,
    required this.dailyCount,
    required this.dueCount,
    required this.loop,
    required this.onStudy,
    required this.onDraw,
    required this.onImport,
    required this.onReview,
  });

  @override
  Widget build(BuildContext context) {
    final ModulePalette p = ModulePalette.of(context);

    final bool hasToday = todayCount > 0;
    final String studyValue = hasToday
        ? '$todayCount 个待学'
        : (drawable > 0 ? '抽 $dailyCount 个' : '导入词表');
    final String studyHint = hasToday ? (loop ? '小循环' : '四步') : '';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: _ModuleCard(
              icon: Icons.play_circle_outline,
              title: '学习',
              value: studyValue,
              hint: studyHint,
              color: p.word,
              fx: TapFx.flipY,
              onTap: hasToday ? onStudy : (drawable > 0 ? onDraw : onImport),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ModuleCard(
              icon: Icons.history_edu,
              title: '复习',
              value: dueCount > 0 ? '$dueCount 个到期' : '暂无到期',
              hint: dueCount > 0 ? '按间隔回来' : '',
              color: p.blue,
              fx: TapFx.pulse,
              onTap: dueCount > 0 ? onReview : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String hint;
  final Color color;
  final TapFx fx;
  final VoidCallback? onTap;

  const _ModuleCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.hint,
    required this.color,
    required this.fx,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ModulePalette p = ModulePalette.of(context);
    final bool enabled = onTap != null;

    return FxTap(
      fx: fx,
      onTap: onTap,
      radius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: enabled ? 0.12 : 0.06),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 19, color: enabled ? color : p.muted),
                ),
                const Spacer(),
                Icon(
                  Icons.arrow_forward,
                  size: 15,
                  color: enabled ? p.muted : p.line,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                color: p.muted,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: enabled ? p.ink : p.muted,
              ),
            ),
            if (hint.isNotEmpty) ...<Widget>[
              const SizedBox(height: 2),
              Text(hint, style: TextStyle(fontSize: 11, color: p.muted)),
            ],
          ],
        ),
      ),
    );
  }
}
