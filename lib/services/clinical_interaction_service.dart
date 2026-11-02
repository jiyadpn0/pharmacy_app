import '../models/erp_models.dart';

enum InteractionSeverity { severe, moderate, info }

class ClinicalInteractionWarning {
  final String drugA;
  final String drugB;
  final String genericA;
  final String genericB;
  final InteractionSeverity severity;
  final String title;
  final String clinicalImpact;
  final String recommendation;

  ClinicalInteractionWarning({
    required this.drugA,
    required this.drugB,
    required this.genericA,
    required this.genericB,
    required this.severity,
    required this.title,
    required this.clinicalImpact,
    required this.recommendation,
  });
}

class ClinicalInteractionService {
  static final ClinicalInteractionService instance = ClinicalInteractionService._internal();
  ClinicalInteractionService._internal();

  /// Evaluates billed items against a clinical interaction matrix
  List<ClinicalInteractionWarning> evaluateInteractions(List<SaleItem> items) {
    List<ClinicalInteractionWarning> warnings = [];

    final validItems = items.where((it) => it.product.name.trim().isNotEmpty && it.qty > 0).toList();
    if (validItems.length < 2) return warnings;

    for (int i = 0; i < validItems.length; i++) {
      for (int j = i + 1; j < validItems.length; j++) {
        final itemA = validItems[i];
        final itemB = validItems[j];

        final genA = itemA.product.genericName.toLowerCase().trim();
        final genB = itemB.product.genericName.toLowerCase().trim();
        final nameA = itemA.product.name.toLowerCase().trim();
        final nameB = itemB.product.name.toLowerCase().trim();

        final combo = "$genA $nameA | $genB $nameB";

        // 1. Anticoagulant + NSAID (Warfarin + Aspirin/Ibuprofen)
        if (_containsAny(combo, ["warfarin", "coumadin"]) &&
            _containsAny(combo, ["aspirin", "ibuprofen", "diclofenac", "naproxen", "ketorolac"])) {
          warnings.add(ClinicalInteractionWarning(
            drugA: itemA.product.name,
            drugB: itemB.product.name,
            genericA: itemA.product.genericName,
            genericB: itemB.product.genericName,
            severity: InteractionSeverity.severe,
            title: "CRITICAL: Major Bleeding Risk",
            clinicalImpact: "Concurrent use of Warfarin and NSAID/Aspirin significantly increases risk of GI bleeding and hemorrhage.",
            recommendation: "Advise prescribing doctor before dispensing. Consider gastro-protective agent.",
          ));
        }

        // 2. PDE5 Inhibitor + Nitrates (Sildenafil + Nitroglycerin)
        if (_containsAny(combo, ["sildenafil", "tadalafil", "vardenafil"]) &&
            _containsAny(combo, ["nitroglycerin", "isosorbide", "nitrate", "sorbitrate"])) {
          warnings.add(ClinicalInteractionWarning(
            drugA: itemA.product.name,
            drugB: itemB.product.name,
            genericA: itemA.product.genericName,
            genericB: itemB.product.genericName,
            severity: InteractionSeverity.severe,
            title: "CRITICAL: Severe Hypotension Risk",
            clinicalImpact: "Co-administration of PDE5 inhibitors with organic nitrates causes profound, life-threatening blood pressure drop.",
            recommendation: "DO NOT DISPENSE together without explicit medical authorization.",
          ));
        }

        // 3. Fluoroquinolone + Antacids / Multivitamins
        if (_containsAny(combo, ["ciprofloxacin", "levofloxacin", "ofloxacin", "moxifloxacin"]) &&
            _containsAny(combo, ["antacid", "calcium", "magnesium", "aluminum", "sucralfate", "iron"])) {
          warnings.add(ClinicalInteractionWarning(
            drugA: itemA.product.name,
            drugB: itemB.product.name,
            genericA: itemA.product.genericName,
            genericB: itemB.product.genericName,
            severity: InteractionSeverity.moderate,
            title: "MODERATE: Reduced Antibiotic Absorption",
            clinicalImpact: "Polyvalent cations bind fluoroquinolones in GI tract, dramatically reducing antibiotic efficacy.",
            recommendation: "Instruct patient to separate dosage by at least 2 to 4 hours.",
          ));
        }

        // 4. ACE Inhibitor / ARB + Potassium Sparing Diuretic
        if (_containsAny(combo, ["enalapril", "lisinopril", "ramipril", "losartan", "valsartan", "telmisartan"]) &&
            _containsAny(combo, ["spironolactone", "eplerenone", "triamterene", "potassium"])) {
          warnings.add(ClinicalInteractionWarning(
            drugA: itemA.product.name,
            drugB: itemB.product.name,
            genericA: itemA.product.genericName,
            genericB: itemB.product.genericName,
            severity: InteractionSeverity.moderate,
            title: "MODERATE: Hyperkalemia Warning",
            clinicalImpact: "Combination can lead to dangerously elevated serum potassium levels.",
            recommendation: "Monitor serum potassium levels regularly.",
          ));
        }

        // 5. Clopidogrel + Omeprazole
        if (_containsAny(combo, ["clopidogrel"]) && _containsAny(combo, ["omeprazole", "esomeprazole"])) {
          warnings.add(ClinicalInteractionWarning(
            drugA: itemA.product.name,
            drugB: itemB.product.name,
            genericA: itemA.product.genericName,
            genericB: itemB.product.genericName,
            severity: InteractionSeverity.moderate,
            title: "MODERATE: Antiplatelet Efficacy Reduction",
            clinicalImpact: "Omeprazole inhibits CYP2C19, reducing activation and therapeutic efficacy of Clopidogrel.",
            recommendation: "Consider alternative PPI such as Pantoprazole or Rabeprazole.",
          ));
        }
      }
    }

    return warnings;
  }

  bool _containsAny(String text, List<String> keywords) {
    for (var k in keywords) {
      if (text.contains(k)) return true;
    }
    return false;
  }
}
