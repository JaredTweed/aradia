import 'package:aradia/resources/designs/app_colors.dart';
import 'package:aradia/screens/home/widgets/favourite_section.dart';
import 'package:aradia/screens/home/widgets/local_imports_section.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:aradia/screens/home/bloc/home_bloc.dart';
import 'package:aradia/screens/home/widgets/my_audiobooks.dart';

import 'widgets/recommended_books_section.dart';
import 'widgets/history_section.dart';
import 'widgets/app_bar_actions.dart';
import 'widgets/welcome_section.dart';
import 'constants/home_constants.dart';
import 'widgets/genre_grid.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  // Keep blocs/controllers stable across theme rebuilds
  late final HomeBloc _popularBloc;
  late final HomeBloc _trendingBloc;

  late final ScrollController _popularCtrl;
  late final ScrollController _trendingCtrl;

  @override
  void initState() {
    super.initState();

    _popularBloc = HomeBloc();
    _trendingBloc = HomeBloc();

    _popularCtrl = ScrollController();
    _trendingCtrl = ScrollController();
  }

  @override
  void dispose() {
    _popularBloc.close();
    _trendingBloc.close();

    _popularCtrl.dispose();
    _trendingCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        title: Text(
          'Aradia',
          style: GoogleFonts.ubuntu(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        actions: [
          AppBarActions(
            onSettingsPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          // --- Welcome section ---
          SliverToBoxAdapter(
            child: WelcomeSection(theme: theme),
          ),
          // --- Recently Played section ---
          SliverToBoxAdapter(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 290),
              child: const HistorySection(),
            ),
          ),
          // --- Local imports section ---
          SliverToBoxAdapter(
            child: LocalImportsSection(),
          ),
          // --- Favourite section ---
          SliverToBoxAdapter(
            child: FavouriteSection(),
          ),
          // --- Recommended genres section ---
          SliverToBoxAdapter(
            child: const RecommendedBooksSection(),
          ),

          // --- Featured sections (popular and trending this week) ---
          SliverToBoxAdapter(
            child: _buildFeaturedSections(),
          ),

          // --- Genres ---
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Browse Genres',
                style: GoogleFonts.ubuntu(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: GenreGrid(genres: HomeConstants.genres),
          ),

          // --- Footer / guidance ---
          SliverToBoxAdapter(
            child: FutureBuilder<Widget>(
              future: _buildGenreSections(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done &&
                    snapshot.hasData) {
                  return snapshot.data!;
                }
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(
                      color: AppColors.primaryColor,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturedSections() {
    return Column(
      children: [
        MyAudiobooks(
          title: 'Popular All Time',
          homeBloc: _popularBloc,
          fetchType: AudiobooksFetchType.popular,
          scrollController: _popularCtrl,
        ),
        MyAudiobooks(
          title: 'Trending This Week',
          homeBloc: _trendingBloc,
          fetchType: AudiobooksFetchType.popularOfWeek,
          scrollController: _trendingCtrl,
        ),
      ],
    );
  }

  Future<Widget> _buildGenreSections() async {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          const SizedBox(height: 16),
          Text(
            'Or Go To Search, Choose Subjects button And Search Your Favorite Genre/s',
            style: GoogleFonts.ubuntu(
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
