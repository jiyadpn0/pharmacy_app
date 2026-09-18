import 'package:flutter/foundation.dart';
import '../models/erp_models.dart';
import '../repositories/master_data_repository.dart';

class MasterDataProvider extends ChangeNotifier {
  final MasterDataRepository _repo;

  MasterDataProvider({MasterDataRepository? repo})
      : _repo = repo ?? MasterDataRepository();

  List<Supplier> _suppliers = [];
  List<Patient> _patients = [];
  List<Doctor> _doctors = [];
  List<Staff> _staff = [];
  List<Map<String, dynamic>> _racks = [];
  List<Map<String, dynamic>> _generics = [];
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _manufacturers = [];
  bool _isLoading = false;

  List<Supplier> get suppliers => List.unmodifiable(_suppliers);
  List<Patient> get patients => List.unmodifiable(_patients);
  List<Doctor> get doctors => List.unmodifiable(_doctors);
  List<Staff> get staff => List.unmodifiable(_staff);
  List<Map<String, dynamic>> get racks => List.unmodifiable(_racks);
  List<Map<String, dynamic>> get generics => List.unmodifiable(_generics);
  List<Map<String, dynamic>> get categories => List.unmodifiable(_categories);
  List<Map<String, dynamic>> get manufacturers => List.unmodifiable(_manufacturers);
  bool get isLoading => _isLoading;

  Future<void> loadAllMasterData() async {
    _isLoading = true;
    notifyListeners();

    try {
      final results = await Future.wait([
        _repo.fetchSuppliers(),
        _repo.fetchPatients(),
        _repo.fetchDoctors(),
        _repo.fetchStaff(),
        _repo.fetchRacks(),
        _repo.fetchGenerics(),
        _repo.fetchCategories(),
        _repo.fetchManufacturers(),
      ]);

      _suppliers = results[0] as List<Supplier>;
      _patients = results[1] as List<Patient>;
      _doctors = results[2] as List<Doctor>;
      _staff = results[3] as List<Staff>;
      _racks = results[4] as List<Map<String, dynamic>>;
      _generics = results[5] as List<Map<String, dynamic>>;
      _categories = results[6] as List<Map<String, dynamic>>;
      _manufacturers = results[7] as List<Map<String, dynamic>>;
    } catch (e) {
      debugPrint("Error loading master data: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Suppliers
  Future<void> addSupplier(Supplier s) async {
    await _repo.insertSupplier(s);
    _suppliers.add(s);
    notifyListeners();
  }

  Future<void> updateSupplier(Supplier s) async {
    await _repo.updateSupplier(s);
    final idx = _suppliers.indexWhere((item) => item.id == s.id);
    if (idx != -1) _suppliers[idx] = s;
    notifyListeners();
  }

  Future<void> deleteSupplier(String id) async {
    await _repo.deleteSupplier(id);
    _suppliers.removeWhere((item) => item.id == id);
    notifyListeners();
  }

  // Patients
  Future<void> addPatient(Patient p) async {
    await _repo.insertPatient(p);
    _patients.add(p);
    notifyListeners();
  }

  Future<void> updatePatient(Patient p) async {
    await _repo.updatePatient(p);
    final idx = _patients.indexWhere((item) => item.id == p.id);
    if (idx != -1) _patients[idx] = p;
    notifyListeners();
  }

  Future<void> deletePatient(String id) async {
    await _repo.deletePatient(id);
    _patients.removeWhere((item) => item.id == id);
    notifyListeners();
  }

  // Doctors
  Future<void> addDoctor(Doctor d) async {
    await _repo.insertDoctor(d);
    _doctors.add(d);
    notifyListeners();
  }

  Future<void> updateDoctor(Doctor d) async {
    await _repo.updateDoctor(d);
    final idx = _doctors.indexWhere((item) => item.id == d.id);
    if (idx != -1) _doctors[idx] = d;
    notifyListeners();
  }

  Future<void> deleteDoctor(String id) async {
    await _repo.deleteDoctor(id);
    _doctors.removeWhere((item) => item.id == id);
    notifyListeners();
  }

  // Staff
  Future<void> addStaff(Staff s) async {
    await _repo.insertStaff(s);
    _staff.add(s);
    notifyListeners();
  }

  Future<void> updateStaff(Staff s) async {
    await _repo.updateStaff(s);
    final idx = _staff.indexWhere((item) => item.id == s.id);
    if (idx != -1) _staff[idx] = s;
    notifyListeners();
  }

  Future<void> deleteStaff(String id) async {
    await _repo.deleteStaff(id);
    _staff.removeWhere((item) => item.id == id);
    notifyListeners();
  }
}
