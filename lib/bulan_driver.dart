import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geocoding/geocoding.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';

class BulanDriver extends StatefulWidget {
  @override
  _BulanDriverState createState() => _BulanDriverState();
}

class _BulanDriverState extends State<BulanDriver> {
  int _selectedIndex = 0;
  List<bool> _seatSelected = List.generate(25, (index) => false);
  final DatabaseReference _databaseRef = FirebaseDatabase.instance.ref().child('/Bulan/Seats');
  late StreamSubscription<DatabaseEvent> _seatDataSubscription;
  Completer<GoogleMapController> _controller = Completer();
  Position? _currentPosition;
  Set<Marker> _markers = Set<Marker>();
  BitmapDescriptor? _customMarkerIcon;
  List<MapType> _mapTypes = MapType.values;
  int _currentMapTypeIndex = 4;
  int _pickupCount = 0;
  BitmapDescriptor? _pickupMarkerIcon; // Add a new variable for the pickup marker icon
  int availableSeats1 = 0;
  int occupiedSeats1 = 0;
  String _selectedRoute = 'Bulan to Sorsogon'; // Default route
  final DatabaseReference _routeRef = FirebaseDatabase.instance.ref('/Bus/BulanBus/Route');





  @override
  void initState() {
    super.initState();
    _loadSeatData();
    _loadCustomMarker();
    _getCurrentLocation();
    /*_loadPickupPoints();
    _loadPickupMarker();*/
    _loadMarkers();
    // Listen for route changes from Firebase
    _routeRef.onValue.listen((event) {
      final String route = event.snapshot.value.toString();
      setState(() {
        _selectedRoute = route;
      });
    });
  }

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error('Location permissions are permanently denied.');
    }

    _currentPosition = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    // Set the initial position and camera view
    setState(() {
      _currentPosition = _currentPosition;
      _updateMarkerPosition(LatLng(_currentPosition!.latitude, _currentPosition!.longitude));
      _updateCameraPosition(LatLng(_currentPosition!.latitude, _currentPosition!.longitude));

      // Send location to Firebase Realtime Database
      FirebaseDatabase.instance.ref().child('Bus/BulanBus/Location').set({
        'latitude': _currentPosition!.latitude,
        'longitude': _currentPosition!.longitude,
      });
    });

    // Listen for location updates and update camera position
    Geolocator.getPositionStream().listen((Position position) {
      setState(() {
        _currentPosition = position;
        _updateMarkerPosition(LatLng(_currentPosition!.latitude, _currentPosition!.longitude));
        _updateCameraPosition(LatLng(_currentPosition!.latitude, _currentPosition!.longitude));

        // Send updated location to Firebase Realtime Database
        FirebaseDatabase.instance.ref().child('Bus/BulanBus/Location').set({
          'latitude': _currentPosition!.latitude,
          'longitude': _currentPosition!.longitude,
        });

        // Load pickup markers whenever the user location updates
        _loadPickupMarker().then((_) {
          _loadPickupPoints(); // Reload pickup points to reflect changes
        });
      });
    });
  }



  Future<void> _updateMarkerPosition(LatLng position) async {
    setState(() {
      _markers = {
        Marker(
          markerId: MarkerId('current_location'),
          position: position,
          icon: _customMarkerIcon ?? BitmapDescriptor.defaultMarker,
        )
      };
    });
  }

  Future<void> _updateCameraPosition(LatLng position) async {
    final GoogleMapController controller = await _controller.future;
    controller.animateCamera(
      CameraUpdate.newLatLng(position),
    );
  }

  void _updateSeatCounts() {
    availableSeats1 = _seatSelected.where((selected) => !selected).length;
    occupiedSeats1 = _seatSelected.where((selected) => selected).length;

    _databaseRef.child('Bulan_Available').set(availableSeats);
    _databaseRef.child('Bulan_Occupied').set(occupiedSeats);
  }


  void _changeMapType(MapType mapType) {
    setState(() {
      _currentMapTypeIndex = _mapTypes.indexOf(mapType);
    });
  }

  Future<void> _loadPickupPoints() async {
    FirebaseFirestore.instance.collection('Pick_Me_Up').snapshots().listen((snapshot) {
      setState(() {
        // Update only pickup points without clearing existing markers
        _pickupCount = snapshot.docs.length; // Update pickup count

        // Create a temporary set for new markers
        Set<Marker> newMarkers = Set<Marker>();

        // Add existing markers
        newMarkers.addAll(_markers);

        snapshot.docs.forEach((doc) {
          GeoPoint geopoint = doc['coordinates'];
          newMarkers.add(
            Marker(
              markerId: MarkerId(doc.id),
              position: LatLng(geopoint.latitude, geopoint.longitude),
              icon: _pickupMarkerIcon ?? BitmapDescriptor.defaultMarker, // Use the pickup marker icon
              infoWindow: InfoWindow(
                title: doc['fullName'],
                snippet: 'Passenger Type: ${doc['passengerType']}',
              ),
            ),
          );
        });

        // Update the markers set
        _markers = newMarkers;
      });
    });
  }


  Future<String> _getAddress(double latitude, double longitude) async {
    try {
      final placemarks = await placemarkFromCoordinates(latitude, longitude);
      final place = placemarks[0];
      return '${place.street}, ${place.subLocality}, ${place.locality}, ${place.administrativeArea}, ${place.country}';
    } catch (e) {
      print("Error getting address: $e");
      return "Unknown address";
    }
  }

  void _onSeatTapped(int index) {
    setState(() {
      _seatSelected[index] = !_seatSelected[index];
      String seatPath = 'Seat${index + 1}';
      _databaseRef.child(seatPath).set(_seatSelected[index]);
      _updateSeatCounts(); // Add this line
    });
  }

  void _loadSeatData() {
    _seatDataSubscription = _databaseRef.onValue.listen((DatabaseEvent event) {
      if (!mounted) return; // Check if the widget is still mounted
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data != null) {
        setState(() {
          _seatSelected = List.generate(25, (index) => data['Seat${index + 1}'] ?? false);
          _updateSeatCounts(); // Add this line
        });
      } else {
        print('No data found in the snapshot.');
      }
    }, onError: (error) {
      print('Error occurred while listening to seat data: $error');
    });
  }


  int get availableSeats => _seatSelected.where((selected) => !selected).length;

  int get occupiedSeats => _seatSelected.where((selected) => selected).length;

  Future<void> _updateStatus(String documentId, String newStatus) async {
    try {
      await FirebaseFirestore.instance.collection('Pick_Me_Up').doc(documentId).update({
        'status': newStatus,
      });
    } catch (e) {
      print("Error updating status: $e");
    }
  }

  Future<void> _deleteDocument(String documentId) async {
    try {
      await FirebaseFirestore.instance.collection('Pick_Me_Up').doc(documentId).delete();
    } catch (e) {
      print("Error deleting document: $e");
    }
  }

  Future<void> _loadMarkers() async {
    await Future.wait([
      _loadCustomMarker(),
      _loadPickupPoints(), // Update this method to handle pickup points
    ]);
  }


  Future<void> _loadCustomMarker() async {
    _customMarkerIcon = await BitmapDescriptor.fromAssetImage(
      ImageConfiguration(size: Size(48, 48)),
      'Imagess/bus2.png',
    );
  }

  Future<void> _loadPickupMarker() async {
    _pickupMarkerIcon = await BitmapDescriptor.fromAssetImage(
      ImageConfiguration(size: Size(48, 48)),
      'Imagess/arm-up.png', // Path to the new pickup marker icon
    );
  }




  Widget _buildPickUpList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('Pick_Me_Up').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Center(child: CircularProgressIndicator());
        }

        final documents = snapshot.data!.docs;

        return DraggableScrollableSheet(
          expand: true,
          builder: (context, scrollController) {
            return Container(
              color: Colors.white,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      'For Pick Up',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Text(
                    'People to Pick Up: $_pickupCount',
                    style: TextStyle(fontSize: 16, color: Colors.blueAccent),
                  ),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(width: 10),
                      Text(
                        'Available Seats: $availableSeats',
                        style: TextStyle(fontSize: 16),
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Occupied Seats: $occupiedSeats',
                        style: TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: documents.length,
                      itemBuilder: (context, index) {
                        final document = documents[index];
                        final documentId = document.id;
                        final fullName = document['fullName'] as String;
                        final geopoint = document['coordinates'] as GeoPoint;
                        final passengerType = document['passengerType'] as String;
                        final status = document['status'] as String;
                        final timestamp = (document['timestamp'] as Timestamp).toDate();
                        final latitude = geopoint.latitude;
                        final longitude = geopoint.longitude;

                        return FutureBuilder<String>(
                          future: _getAddress(latitude, longitude),
                          builder: (context, addressSnapshot) {
                            if (!addressSnapshot.hasData) {
                              return ListTile(
                                title: Text(fullName),
                                subtitle: Text('Fetching address...'),
                                contentPadding: EdgeInsets.all(16),
                              );
                            }

                            final address = addressSnapshot.data!;

                            return Card(
                              elevation: 5,
                              margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                              child: ListTile(
                                contentPadding: EdgeInsets.all(16),
                                title: Text(
                                  fullName,
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          'Passenger Type: $passengerType',
                                          style: TextStyle(fontSize: 16, color: Colors.grey[800], fontWeight: FontWeight.bold),
                                        ),
                                        SizedBox(width: 10,),
                                        Text(
                                          'Status: $status',
                                          style: TextStyle(fontSize: 16, color: Colors.grey[800], fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: 5),
                                    Text(
                                      'Address: $address',
                                      style: TextStyle(fontSize: 16),
                                    ),
                                    SizedBox(height: 5),
                                    Text(
                                      'Requested at: ${timestamp.toLocal()}',
                                      style: TextStyle(fontSize: 16),
                                    ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        TextButton(
                                          onPressed: () {
                                            _updateStatus(documentId, 'Accepted');
                                          },
                                          child: Text('Accept', style: TextStyle(color: Colors.green)),
                                        ),
                                        TextButton(
                                          onPressed: () {
                                            _updateStatus(documentId, 'Declined');
                                          },
                                          child: Text('Decline', style: TextStyle(color: Colors.red)),
                                        ),
                                        TextButton(
                                          onPressed: () {
                                            _deleteDocument(documentId);
                                          },
                                          child: Text('Delete', style: TextStyle(color: Colors.red)),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),

                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFloatingTextWithMenu() {
    return Positioned(
      top: 20,
      left: 20,
      child: GestureDetector(
        onTap: () {
          // Show the popup menu
          _showPopupMenu();
        },
        child: Material(
          color: Colors.transparent,
          child: Row(
            children: [
              // Floating text
              Container(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Colors.black.withOpacity(0.5),
                child: Text(
                  'Route Selector',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
              SizedBox(width: 10),
              // Popup menu button (hidden, just for appearance)
              Icon(Icons.swap_horiz, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }

  void _showPopupMenu() async {
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final Offset offset = renderBox.localToGlobal(Offset.zero);

    await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + 40,
        offset.dx + renderBox.size.width,
        offset.dy,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'Bulan to Sorsogon',
          child: Text('Bulan to Sorsogon'),
        ),
        PopupMenuItem<String>(
          value: 'Sorsogon to Bulan',
          child: Text('Sorsogon to Bulan'),
        ),
      ],
      initialValue: null,
    ).then((String? value) {
      if (value != null) {
        _updateRouteInFirebase(value);
      }
    });
  }

  void _updateRouteInFirebase(String route) {
    FirebaseDatabase.instance.ref().child('/Bus/BulanBus/Route').set(route);
  }



  Widget _buildSeats() {
    return Stack(
      children: [
        _buildMap(),
        DraggableScrollableSheet(
          expand: true,
          builder: (context, scrollController) {
            return Container(
              color: Colors.white,
              child: SingleChildScrollView(
                controller: scrollController,
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          height: 5,
                          width: 100,
                          margin: EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.grey,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ],
                    ),
                    Text("Driver Seat", style: TextStyle(fontSize: 18)),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(width: 10),
                        Text(
                          'Available Seats: $availableSeats',
                          style: TextStyle(fontSize: 16),
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Occupied Seats: $occupiedSeats',
                          style: TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                    SizedBox(height: 10),
                    _buildSeatRow([0], "Driver"),
                    SizedBox(height: 20),
                    _buildSeatRow([1, 2, null, null, 3]),
                    SizedBox(height: 20),
                    _buildSeatRow([4, 5, null, null, 6]),
                    SizedBox(height: 20),
                    _buildSeatRow([7, 8, null, null, null, null]),
                    SizedBox(height: 20),
                    _buildSeatRow([9, 10, null, null, 11]),
                    SizedBox(height: 20),
                    _buildSeatRow([12, 13, null, null, 14]),
                    SizedBox(height: 20),
                    _buildSeatRow([15, 16, null, null, 17]),
                    SizedBox(height: 20),
                    _buildSeatRow([18, 19, null, null, 20]),
                    SizedBox(height: 20),
                    _buildSeatRow([21, 22, 23, 24]),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildSeatRow(List<int?> seatIndices, [String? label]) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.all(4.0),
            child: Text(label, style: TextStyle(fontSize: 16)),
          ),
        ...seatIndices.map((index) {
          if (index == null || index >= _seatSelected.length) {
            return SizedBox(width: 30); // Adjust spacing as necessary
          } else {
            return Padding(
              padding: const EdgeInsets.all(4.0),
              child: GestureDetector(
                onTap: () => _onSeatTapped(index),
                child: Container(
                  width: 50, // Adjust width as necessary
                  height: 50, // Adjust height as necessary
                  decoration: BoxDecoration(
                    color: _seatSelected[index] ? Colors.green : Colors.grey,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: Center(
                    child: Text(
                      "Seat ${index + 1}",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }
        }).toList(),
      ],
    );
  }

  @override
  void dispose() {
    _seatDataSubscription.cancel(); // Cancel the stream subscription
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Driver', style: TextStyle(fontSize: 18),),
        actions: [
          PopupMenuButton<MapType>(
            icon: Icon(Icons.map),
            onSelected: (MapType mapType) {
              _changeMapType(mapType);
            },
            itemBuilder: (context) => MapType.values.map((mapType) {
              return PopupMenuItem<MapType>(
                value: mapType,
                child: Text(mapType.toString().split('.').last),
              );
            }).toList(),
          ),
          SizedBox(width: 10),
          PopupMenuButton<String>(
            onSelected: (String route) {
              setState(() {
                _selectedRoute = route;
                // Update Firebase Database with the selected route
                FirebaseDatabase.instance.ref().child('/Bus/BulanBus/Route').set(_selectedRoute);
              });
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: 'Bulan to Sorsogon',
                child: Text('Bulan to\nSorsogon'),
              ),
              PopupMenuItem<String>(
                value: 'Sorsogon to Bulan',
                child: Text('Sorsogon to\nBulan'),
              ),
            ],
            child: Row(
              children: [
                Icon(Icons.directions_bus),
                SizedBox(width: 8),
                Text('Routes'),
                Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
          SizedBox(width: 10),
        ],
      ),
      body: Stack(
        children: [
          _buildMap(),
          Positioned(
            top: 20.0,
            left: 50.0,
            right: 50.0,
            child: Container(
              padding: EdgeInsets.all(8.0),
              constraints: BoxConstraints(
                maxWidth: 300.0, // Adjust this value to fit approximately 30 characters
              ),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.6),
                borderRadius: BorderRadius.circular(12.0),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Route: ' ,style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),),
                  Text(
                    _selectedRoute, // Display the route text
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),


          _selectedIndex == 0 ? _buildPickUpList() : _buildSeats(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        items: [
          BottomNavigationBarItem(
            icon: Icon(Icons.directions_car),
            label: 'For Pick Up',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.event_seat),
            label: 'Seats',
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    return _currentPosition == null
        ? Center(child: CircularProgressIndicator())
        : GoogleMap(
      initialCameraPosition: CameraPosition(
        target: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        zoom: 16.0,
      ),
      markers: _markers,
      myLocationEnabled: true,
      myLocationButtonEnabled: true,
      onMapCreated: (GoogleMapController controller) {
        _controller.complete(controller);
      },
      mapType: _mapTypes[_currentMapTypeIndex], // Use selected map type
    );
  }

  void main() {
    runApp(MaterialApp(
      home: BulanDriver(),
    ));
  }
}
