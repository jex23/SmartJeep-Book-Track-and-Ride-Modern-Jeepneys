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
  MapType _currentMapType = MapType.normal;
  int _selectedIndex = 0;
  BitmapDescriptor? customIcon;

  // Initialize a list with default boolean values set to false for each seat
  List<bool> _seatSelected = List.generate(25, (index) => false);

  final DatabaseReference _databaseRef = FirebaseDatabase.instance.ref().child('Seats');

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _loadSeatData(); // Load initial seat data from Firebase
    _loadCustomMarker();
  }

  Future<void> _loadCustomMarker() async {
    customIcon = await BitmapDescriptor.fromAssetImage(
      ImageConfiguration(size: Size(1, 1)),
      'Imagess/jeepney.png',
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
        _address = "${place.thoroughfare}, ${place.locality}, ${place.administrativeArea}, ${place.country}";
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

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _onSeatTapped(int index) {
    setState(() {
      // Toggle the boolean value for the seat
      _seatSelected[index] = !_seatSelected[index];
      // Update the seat status in Firebase
      String seatPath = 'Seat${index + 1}'; // Path: Seat1, Seat2, etc.
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

  Widget _buildMap() {
    return Column(
      children: [
        Container(
          height: 300.0,
          child: Stack(
            children: [
              GoogleMap(
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
                  Marker(
                    markerId: MarkerId('currentLocation'),
                    position: _initialPosition,
                    icon: customIcon ?? BitmapDescriptor.defaultMarker,
                  ),
                },
              ),
              Positioned(
                bottom: 100,
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
                        child: Text('Hybrid'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(_address, style: TextStyle(fontSize: 18)),
        ),
      ],
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
                    color: _seatSelected[index] ? Colors.green : Colors.grey, // Color based on seat status
                    borderRadius: BorderRadius.circular(8), // Rounded corners
                    border: Border.all(color: Colors.black12), // Optional border
                  ),
                  child: Center(
                    child: Text(
                      "Seat ${index + 1}",
                      style: TextStyle(
                        color: Colors.white, // Text color
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Driver Page'),
      ),
      body: SingleChildScrollView(
        child: _selectedIndex == 0 ? _buildMap() : _buildSeats(),
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.map),
            label: 'Map',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.event_seat),
            label: 'Seats',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.blue,
        onTap: _onItemTapped,
      ),
    );
  }
}

void main() => runApp(MaterialApp(home: DriverPage()));
