import 'dart:async'; // Import for StreamSubscription
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:firebase_database/firebase_database.dart'; // Import Firebase Realtime Database

class DriverPage extends StatefulWidget {
  @override
  _DriverPageState createState() => _DriverPageState();
}

class _DriverPageState extends State<DriverPage> {
  String _address = "Fetching address...";
  GoogleMapController? _mapController;
  LatLng _initialPosition = LatLng(0, 0);
  MapType _currentMapType = MapType.hybrid;
  BitmapDescriptor? customIcon;
  Marker? _currentLocationMarker;

  // Initialize a list with default boolean values set to false for each seat
  List<bool> _seatSelected = List.generate(25, (index) => false);

  final DatabaseReference _databaseRef = FirebaseDatabase.instance.ref().child('Seats');

  // State variables
  bool _showSeats = false;
  bool _isExpanded = false;
  late StreamSubscription<Position> _positionStreamSubscription;

  final DraggableScrollableController _draggableController = DraggableScrollableController();

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _loadSeatData(); // Load initial seat data from Firebase
    _loadCustomMarker();
    _startLocationUpdates(); // Start location updates
  }

  Future<void> _loadCustomMarker() async {
    customIcon = await BitmapDescriptor.fromAssetImage(
      ImageConfiguration(size: Size(45, 45)),
      'Imagess/bus2.png',
    );
  }

  Future<void> _checkPermissions() async {
    if (await Permission.location.request().isGranted) {
      _getCurrentLocation();
    } else {
      setState(() {
        _address = "Location permission denied";
      });
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      setState(() {
        _initialPosition = LatLng(position.latitude, position.longitude);
      });
      _mapController?.animateCamera(CameraUpdate.newLatLng(_initialPosition));
      _getAddressFromLatLng(position);
    } catch (e) {
      setState(() {
        _address = "Error getting location";
      });
    }
  }

  Future<void> _getAddressFromLatLng(Position position) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
      Placemark place = placemarks[0];
      setState(() {
        _address = "${place.street ?? 'Unknown Street'}, ${place.locality ?? 'Unknown Locality'}, ${place.administrativeArea ?? 'Unknown Area'}, ${place.country ?? 'Unknown Country'}";
      });
    } catch (e) {
      setState(() {
        _address = "Error fetching address";
      });
    }
  }

  void _onMapTypeChanged(MapType mapType) {
    setState(() {
      _currentMapType = mapType;
    });
  }

  void _onSeatTapped(int index) {
    setState(() {
      _seatSelected[index] = !_seatSelected[index];
      String seatPath = 'Seat${index + 1}';
      _databaseRef.child(seatPath).set(_seatSelected[index]);
    });
  }

  Future<void> _loadSeatData() async {
    _databaseRef.onValue.listen((DatabaseEvent event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data != null) {
        setState(() {
          _seatSelected = List.generate(25, (index) => data['Seat${index + 1}'] ?? false);
        });
      }
    });
  }

  int get availableSeats => _seatSelected.where((selected) => !selected).length;
  int get occupiedSeats => _seatSelected.where((selected) => selected).length;

  Widget _buildMap() {
    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: _initialPosition,
        zoom: 14.0,
      ),
      mapType: _currentMapType,
      onMapCreated: (GoogleMapController controller) {
        _mapController = controller;
      },
      myLocationEnabled: true,
      myLocationButtonEnabled: true,
      markers: {
        if (_currentLocationMarker != null) _currentLocationMarker!,
      },
    );
  }

  Widget _buildSeats() {
    return SingleChildScrollView(
      child: Column(
        children: [
          Text("Driver Seat", style: TextStyle(fontSize: 18)),
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

  void _expandSheet() {
    _draggableController.animateTo(
      0.6, // Adjust this value if needed to fit your design
      duration: Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _startLocationUpdates() {
    _positionStreamSubscription = Geolocator.getPositionStream(
      // Use the correct parameters based on the latest Geolocator API
    ).listen((Position position) {
      setState(() {
        _initialPosition = LatLng(position.latitude, position.longitude);
        _currentLocationMarker = Marker(
          markerId: MarkerId('currentLocation'),
          position: _initialPosition,
          icon: customIcon ?? BitmapDescriptor.defaultMarker,
        );
        _mapController?.animateCamera(CameraUpdate.newLatLng(_initialPosition));
        _getAddressFromLatLng(position);
      });
    });
  }

  @override
  void dispose() {
    _positionStreamSubscription.cancel(); // Cancel location updates when not needed
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final safeAreaBottom = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      body: Stack(
        children: [
          _buildMap(),
          DraggableScrollableSheet(
            initialChildSize: 0.3,
            minChildSize: 0.2,
            maxChildSize: 0.6,
            controller: _draggableController,
            builder: (BuildContext context, ScrollController scrollController) {
              return GestureDetector(
                onVerticalDragUpdate: (details) {
                  // Allow the sheet to be dragged up and down
                },
                onTap: () {
                  setState(() {
                    _isExpanded = !_isExpanded;
                    _draggableController.animateTo(
                      _isExpanded ? 0.6 : 0.3,
                      duration: Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  });
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 10,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Container(
                        height: 5,
                        width: 40,
                        margin: EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.grey,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            left: 16.0,
                            right: 16.0,
                            bottom: safeAreaBottom + 8.0,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _address,
                                style: TextStyle(fontSize: 18),
                              ),
                              SizedBox(height: 10),
                              Row(
                                children: [
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
                              // Navigation Bar for "For Pick Up" and "Seats"
                              Container(
                                color: Colors.blue,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                                  children: [
                                    Expanded(
                                      child: TextButton(
                                        onPressed: () {
                                          setState(() {
                                            _showSeats = false; // Hide seats when "For Pick Up" is clicked
                                          });
                                          _expandSheet(); // Ensure the sheet is fully extended
                                        },
                                        child: Text(
                                          'For Pick Up',
                                          style: TextStyle(color: Colors.white),
                                        ),
                                      ),
                                    ),
                                    Container(
                                      height: 24,
                                      width: 1,
                                      color: Colors.white,
                                    ),
                                    Expanded(
                                      child: TextButton(
                                        onPressed: () {
                                          setState(() {
                                            _showSeats = true; // Show seats when "Seats" is clicked
                                          });
                                          _expandSheet(); // Ensure the sheet is fully extended
                                        },
                                        child: Text(
                                          'Seats',
                                          style: TextStyle(color: Colors.white),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: ListView(
                                    controller: scrollController,
                                    children: [
                                      _showSeats ? _buildSeats() : Container(),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          Positioned(
            top: 80,
            right: 10,
            child: FloatingActionButton(
              onPressed: () {},
              child: PopupMenuButton<MapType>(
                icon: Icon(Icons.map),
                onSelected: _onMapTypeChanged,
                itemBuilder: (BuildContext context) => <PopupMenuEntry<MapType>>[
                  const PopupMenuItem<MapType>(
                    value: MapType.normal,
                    child: Text('Normal'),
                  ),
                  const PopupMenuItem<MapType>(
                    value: MapType.satellite,
                    child: Text('Satellite'),
                  ),
                  const PopupMenuItem<MapType>(
                    value: MapType.terrain,
                    child: Text('Terrain'),
                  ),
                  const PopupMenuItem<MapType>(
                    value: MapType.hybrid,
                    child: Text('Hybrid'), //
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void main() => runApp(MaterialApp(home: DriverPage()));
