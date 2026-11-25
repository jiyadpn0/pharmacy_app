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

  /// Returns true if any severe (critical) interaction is detected among billed items
  bool hasSevereInteractions(List<SaleItem> items) {
    final warnings = evaluateInteractions(items);
    return warnings.any((w) => w.severity == InteractionSeverity.severe);
  }

  /// Evaluates billed items against the clinical interaction matrix
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

        // 1. Anticoagulant + NSAID (Warfarin/Acenocoumarol + Aspirin/Ibuprofen/Diclofenac)
        if (_containsAny(combo, ["warfarin", "coumadin", "acenocoumarol", "nicoumalone", "dabigatran", "apixaban", "rivaroxaban"]) &&
            _containsAny(combo, ["aspirin", "ibuprofen", "diclofenac", "naproxen", "ketorolac", "aceclofenac", "piroxicam", "mefenamic"])) {
          warnings.add(ClinicalInteractionWarning(
            drugA: itemA.product.name,
            drugB: itemB.product.name,
            genericA: itemA.product.genericName,
            genericB: itemB.product.genericName,
            severity: InteractionSeverity.severe,
            title: "CRITICAL: Major Bleeding & Hemorrhage Risk",
            clinicalImpact: "Concurrent use of anticoagulant and NSAID dramatically increases risk of severe gastrointestinal bleeding and systemic hemorrhage.",
            recommendation: "Advise prescribing doctor before dispensing. Consider gastro-protective co-therapy (e.g. PPI).",
          ));
        }

        // 2. PDE5 Inhibitor + Nitrates (Sildenafil/Tadalafil + Nitroglycerin/Sorbitrate)
        if (_containsAny(combo, ["sildenafil", "tadalafil", "vardenafil", "avanafil"]) &&
            _containsAny(combo, ["nitroglycerin", "isosorbide", "nitrate", "sorbitrate", "mononitrate", "dinitrate"])) {
          warnings.add(ClinicalInteractionWarning(
            drugA: itemA.product.name,
            drugB: itemB.product.name,
            genericA: itemA.product.genericName,
            genericB: itemB.product.genericName,
            severity: InteractionSeverity.severe,
            title: "CRITICAL: Severe Life-Threatening Hypotension",
            clinicalImpact: "Co-administration of PDE5 inhibitors with organic nitrates causes profound, synergistic, life-threatening blood pressure drop and circulatory collapse.",
            recommendation: "DO NOT DISPENSE together without explicit cardiologist authorization.",
          ));
        }

        // 3. Statin + Macrolide / Azole (Atorvastatin/Simvastatin + Clarithromycin/Itraconazole)
        if (_containsAny(combo, ["atorvastatin", "simvastatin", "lovastatin", "rosuvastatin"]) &&
            _containsAny(combo, ["clarithromycin", "erythromycin", "itraconazole", "ketoconazole", "fluconazole"])) {
          warnings.add(ClinicalInteractionWarning(
            drugA: itemA.product.name,
            drugB: itemB.product.name,
            genericA: itemA.product.genericName,
            genericB: itemB.product.genericName,
            severity: InteractionSeverity.severe,
            title: "CRITICAL: Severe Rhabdomyolysis & Kidney Failure Risk",
            clinicalImpact: "Macrolides and Azoles strongly inhibit CYP3A4, dramatically elevating serum statin concentrations and triggering severe muscle breakdown (rhabdomyolysis).",
            recommendation: "Suspend statin therapy temporarily during antibiotic/antifungal course or consult doctor.",
          ));
        }

        // 4. Beta-Blocker + Non-DHP Calcium Channel Blocker (Atenolol/Metoprolol + Verapamil/Diltiazem)
        if (_containsAny(combo, ["atenolol", "metoprolol", "propranolol", "bisoprolol", "carvedilol", "nebivolol"]) &&
            _containsAny(combo, ["verapamil", "diltiazem"])) {
          warnings.add(ClinicalInteractionWarning(
            drugA: itemA.product.name,
            drugB: itemB.product.name,
            genericA: itemA.product.genericName,
            genericB: itemB.product.genericName,
            severity: InteractionSeverity.severe,
            title: "CRITICAL: Severe Bradycardia & AV Heart Block",
            clinicalImpact: "Additive negative chronotropic and inotropic effects may cause severe bradycardia, heart block, and cardiogenic shock.",
            recommendation: "Requires close cardiac monitoring. Do not dispense without verifying doctor's intentional co-prescription.",
          ));
        }

        // 5. Methotrexate + NSAIDs (Methotrexate + Diclofenac/Ibuprofen)
        if (_containsAny(combo, ["methotrexate"]) &&
            _containsAny(combo, ["aspirin", "ibuprofen", "diclofenac", "naproxen", "ketorolac", "aceclofenac"])) {
          warnings.add(ClinicalInteractionWarning(
            drugA: itemA.product.name,
            drugB: itemB.product.name,
            genericA: itemA.product.genericName,
            genericB: itemB.product.genericName,
            severity: InteractionSeverity.severe,
            title: "CRITICAL: Methotrexate Toxicity & Bone Marrow Suppression",
            clinicalImpact: "NSAIDs reduce renal clearance of Methotrexate, causing fatal bone marrow suppression and gastrointestinal toxicity.",
            recommendation: "Avoid concurrent use unless strictly supervised by an oncologist/rheumatologist.",
          ));
        }

        // 6. Tramadol + SSRI / SNRI (Tramadol + Sertraline/Fluoxetine/Escitalopram)
        if (_containsAny(combo, ["tramadol"]) &&
            _containsAny(combo, ["sertraline", "fluoxetine", "escitalopram", "citalopram", "paroxetine", "duloxetine", "venlafaxine"])) {
          warnings.add(ClinicalInteractionWarning(
            drugA: itemA.product.name,
            drugB: itemB.product.name,
            genericA: itemA.product.genericName,
            genericB: itemB.product.genericName,
            severity: InteractionSeverity.severe,
            title: "CRITICAL: Serotonin Syndrome & Seizure Risk",
            clinicalImpact: "Combined serotonergic activity significantly increases the risk of potentially fatal Serotonin Syndrome and lowered seizure threshold.",
            recommendation: "Alert prescriber. Monitor for agitation, hyperthermia, tremor, or seizures.",
          ));
        }

        // 7. Fluoroquinolone + Antacids / Multivitamins
        if (_containsAny(combo, ["ciprofloxacin", "levofloxacin", "ofloxacin", "moxifloxacin", "norfloxacin"]) &&
            _containsAny(combo, ["antacid", "calcium", "magnesium", "aluminum", "sucralfate", "iron", "zinc"])) {
          warnings.add(ClinicalInteractionWarning(
            drugA: itemA.product.name,
            drugB: itemB.product.name,
            genericA: itemA.product.genericName,
            genericB: itemB.product.genericName,
            severity: InteractionSeverity.moderate,
            title: "MODERATE: Chelation & Reduced Antibiotic Efficacy",
            clinicalImpact: "Polyvalent metal cations bind fluoroquinolones in the GI tract, dramatically reducing antibiotic absorption and clinical efficacy.",
            recommendation: "Instruct patient to separate dosages by at least 2 hours before or 4 hours after antacids.",
          ));
        }

        // 8. ACE Inhibitor / ARB + Potassium Sparing Diuretic
        if (_containsAny(combo, ["enalapril", "lisinopril", "ramipril", "losartan", "valsartan", "telmisartan", "olmesartan"]) &&
            _containsAny(combo, ["spironolactone", "eplerenone", "triamterene", "potassium"])) {
          warnings.add(ClinicalInteractionWarning(
            drugA: itemA.product.name,
            drugB: itemB.product.name,
            genericA: itemA.product.genericName,
            genericB: itemB.product.genericName,
            severity: InteractionSeverity.moderate,
            title: "MODERATE: Hyperkalemia Risk",
            clinicalImpact: "Combination can lead to dangerously elevated serum potassium levels causing cardiac arrhythmias.",
            recommendation: "Periodic serum potassium monitoring is strongly advised.",
          ));
        }

        // 9. Clopidogrel + Omeprazole
        if (_containsAny(combo, ["clopidogrel"]) && _containsAny(combo, ["omeprazole", "esomeprazole"])) {
          warnings.add(ClinicalInteractionWarning(
            drugA: itemA.product.name,
            drugB: itemB.product.name,
            genericA: itemA.product.genericName,
            genericB: itemB.product.genericName,
            severity: InteractionSeverity.moderate,
            title: "MODERATE: Antiplatelet Efficacy Reduction",
            clinicalImpact: "Omeprazole inhibits CYP2C19, significantly reducing bio-activation and antiplatelet efficacy of Clopidogrel.",
            recommendation: "Recommend an alternative PPI with minimal CYP2C19 inhibition (e.g. Pantoprazole, Rabeprazole).",
          ));
        }

        // 10. Levothyroxine + Calcium / Iron
        if (_containsAny(combo, ["levothyroxine", "thyroxine", "eltroxin"]) &&
            _containsAny(combo, ["calcium", "iron", "ferrous", "ferric"])) {
          warnings.add(ClinicalInteractionWarning(
            drugA: itemA.product.name,
            drugB: itemB.product.name,
            genericA: itemA.product.genericName,
            genericB: itemB.product.genericName,
            severity: InteractionSeverity.moderate,
            title: "MODERATE: Reduced Thyroid Hormone Absorption",
            clinicalImpact: "Calcium and iron supplements interfere with absorption of Levothyroxine in the gut, causing sub-therapeutic thyroid levels.",
            recommendation: "Advise patient to take Levothyroxine on an empty stomach at least 4 hours apart from calcium/iron.",
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
