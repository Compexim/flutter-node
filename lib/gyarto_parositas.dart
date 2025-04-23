// gyarto_parositas.dart (Drag & Drop kész, automatikus frissítés mindkét oldalon)
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'unmatched_suppliers_list.dart';

class GyartoParositasPage extends StatefulWidget {
  const GyartoParositasPage({super.key});

  @override
  State<GyartoParositasPage> createState() => GyartoParositasPageState();
}

class GyartoParositasPageState extends State<GyartoParositasPage> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final GlobalKey<UnmatchedSuppliersListState> _suppliersListKey = GlobalKey();

  List<Map<String, dynamic>> manufacturers = [];
  int page = 1;
  bool isLoading = false;
  bool hasMore = true;

  @override
  void initState() {
    super.initState();
    _fetchManufacturers();

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent - 100 &&
          !isLoading &&
          hasMore) {
        _fetchManufacturers();
      }
    });
  }

  void refreshManufacturers() {
  setState(() {
    manufacturers.clear();
    page = 1;
  });
  _fetchManufacturers(isSearch: true);
}


  Future<void> _fetchManufacturers({bool isSearch = false}) async {
    setState(() => isLoading = true);

    if (isSearch) {
      page = 1;
      manufacturers.clear();
      hasMore = true;
    }

    final uri = Uri.parse(
        'http://localhost:3000/api/manufacturers-with-aliases?page=$page&search=${_searchController.text}');

    try {
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);

        final List<Map<String, dynamic>> newItems = data.map((item) {
          final aliasesRaw = item['aliases'];
          final List<Map<String, dynamic>> aliasesList = aliasesRaw is List
             ? aliasesRaw
                .where((e) => e != null && e is Map<String, dynamic>)
                .map((e) => {'id': e['id'], 'name': e['name']})
                .toList()
              : [];

          return {
            'id': item['id'],
            'name': item['name'],
            'aliases': aliasesList,
            'has_exact_match': item['has_exact_match'],
          };
        }).toList();

        setState(() {
          manufacturers.addAll(newItems);
          page++;
          if (newItems.length < 20) hasMore = false;
        });
      } else {
        print('Hibás API válasz: ${response.statusCode}');
      }
    } catch (e) {
      print('API hívás hiba: $e');
    }

    setState(() => isLoading = false);
  }

  Future<void> _pairManufacturer(String supplierId, String manufacturerId) async {
    final uri = Uri.parse('http://localhost:3000/api/pair-manufacturer');

    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'supplier_manufacturer_id': supplierId,
          'manufacturer_id': manufacturerId,
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('Párosítás sikeres');
        setState(() {
        manufacturers.clear();
        page = 1;
      });
        _fetchManufacturers(isSearch: true);
        _suppliersListKey.currentState?.refreshList(); // ← EZ FRISSÍTI A JOBB OLDALT
      }
 else {
        print('Hiba: ${response.statusCode}');
      }
    } catch (e) {
      print('API hiba: $e');
    }
  }

 
Widget _buildManufacturerCard(Map<String, dynamic> manufacturer) {
  final name = manufacturer['name'] as String;
  final aliases = manufacturer['aliases'] as List<Map<String, dynamic>>;
  final id = manufacturer['id'] as String;
  final hasExactMatch = manufacturer['has_exact_match'] == true;

  void showManufacturerMenu(BuildContext context, Offset position) async {
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: [
        PopupMenuItem<String>(
          value: 'unpair_all',
          child: Text('Gyátó + Alias leválasztása'),
        ),
      ],
    );

    if (selected == 'unpair_all') {
      try {
          final response = await http.post(
            Uri.parse('http://localhost:3000/api/unpair-all'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'manufacturer_id': id}),
          );
          if (response.statusCode == 200) {
            _fetchManufacturers(isSearch: true);
            _suppliersListKey.currentState?.refreshList();
          } else {
            debugPrint('Leválasztás sikertelen: ${response.statusCode}');
          }
        } catch (e) {
          debugPrint('Hiba leválasztás közben: $e');
        }

      // TODO: backend hívás - unpair all
    }
  }

 void showAliasMenu(BuildContext context, Offset position, Map<String, dynamic> alias) async {
  final selected = await showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
    items: [
      PopupMenuItem<String>(
        value: 'unpair_one',
        child: Text('Alias leválasztása'),
      ),
    ],
  );

  if (selected == 'unpair_one') {
    final supplierManufacturerId = alias['id'];

    try {
      final response = await http.post(
        Uri.parse('http://localhost:3000/api/unpair-alias'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'supplier_manufacturer_id': supplierManufacturerId}),
      );
      if (response.statusCode == 200) {
        _fetchManufacturers(isSearch: true);
        _suppliersListKey.currentState?.refreshList();
      } else {
        debugPrint('Alias leválasztása sikertelen: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Hiba alias leválasztás közben: $e');
    }
  }
}


  return Card(
    elevation: 2,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    color: Colors.white,
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    child: Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onSecondaryTapDown: (details) =>
                showManufacturerMenu(context, details.globalPosition),
            child: Row(
  mainAxisAlignment: MainAxisAlignment.spaceBetween,
  children: [
    Expanded(
      child: Text(
        name,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
          color: Color(0xFF111827),
        ),
        overflow: TextOverflow.ellipsis,
      ),
    ),
    if (hasExactMatch)
      Icon(Icons.link, size: 16, color: Color(0xFF6C5DD3)),
  ],
),

          ),
          ...aliases.map((alias) => Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: GestureDetector(
                onSecondaryTapDown: (details) =>
                  showAliasMenu(context, details.globalPosition, alias),
                child: Text(
                  '+ ${alias['name']}',
                  style: TextStyle(fontSize: 12, color: Colors.green[700]),
                ),
              ),
            ))

        ],
      ),
    ),
  );
}



  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          toolbarHeight: 40,
          title: Text(
            'Gyártók párosításítása',
            style: TextStyle(color: const Color.fromARGB(255, 126, 14, 134)),
          ),
          backgroundColor: const Color.fromARGB(255, 248, 241, 249)),
      body: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Szűrés saját gyártóra vagy aliasra...',
                      suffixIcon: IconButton(
                        icon: Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _fetchManufacturers(isSearch: true);
                        },
                      ),
                    ),
                    onChanged: (_) {
                      _fetchManufacturers(isSearch: true);
                    },
                    onSubmitted: (_) {
                      _fetchManufacturers(isSearch: true);
                    },
                  ),
                ),
                Expanded(
                  child: manufacturers.isEmpty && !isLoading
                      ? Center(child: Text('Nincs találat vagy adat!'))
                      : ListView.builder(
                          controller: _scrollController,
                          itemCount: manufacturers.length + (hasMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index >= manufacturers.length) {
                              return Center(
                                  child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: CircularProgressIndicator(),
                              ));
                            }

                            final manufacturer = manufacturers[index];
                            return DragTarget<Map<String, dynamic>>(
                              onWillAcceptWithDetails: (data) => true,
                              onAcceptWithDetails: (DragTargetDetails<Map<String, dynamic>> details) async {
                                final supplier = details.data;
                                await _pairManufacturer(supplier['id'].toString(), manufacturer['id']);
                              },

                              builder: (context, candidateData, rejectedData) {
                                return _buildManufacturerCard(manufacturer);
                              },
                            );

                          },
                        ),
                ),
              ],
            ),
          ),
          VerticalDivider(width: 1),
          Expanded(
            child: UnmatchedSuppliersList(key: _suppliersListKey, isDraggable: true),
          ),
        ],
      ),
    );
  }
}
