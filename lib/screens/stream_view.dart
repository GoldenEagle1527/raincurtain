import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/pool_manager.dart';
import '../widgets/pool_card.dart';
import 'pool_detail_page.dart';

class StreamView extends StatelessWidget {
  const StreamView({super.key});

  @override
  Widget build(BuildContext context) {
    final poolManager = context.watch<PoolManager>();

    if (!poolManager.isInit) {
      return const Center(child: CircularProgressIndicator());
    }

    final pools = poolManager.pools;

    if (pools.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.water_drop_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              '还没有池',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '点击右下角按钮创建第一个池',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 400,
        childAspectRatio: 1.6,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: pools.length,
      itemBuilder: (context, index) {
        final pool = pools[index];
        return PoolCard(
          pool: pool,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PoolDetailPage(poolId: pool.id),
              ),
            );
          },
        );
      },
    );
  }
}
