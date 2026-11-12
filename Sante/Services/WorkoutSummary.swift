import Foundation
import HealthKit

struct WorkoutSummary: Identifiable {
    let id: UUID
    let type: HKWorkoutActivityType
    let start: Date
    let duration: TimeInterval
    let kcal: Double?
    let distanceKm: Double?

    init(workout: HKWorkout) {
        id = workout.uuid
        type = workout.workoutActivityType
        start = workout.startDate
        duration = workout.duration
        kcal = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?
            .sumQuantity()?.doubleValue(for: .kilocalorie())
        let distanceTypes: [HKQuantityTypeIdentifier] = [.distanceWalkingRunning, .distanceCycling, .distanceSwimming]
        distanceKm = distanceTypes.lazy
            .compactMap { workout.statistics(for: HKQuantityType($0))?.sumQuantity() }
            .first?
            .doubleValue(for: .meterUnit(with: .kilo))
    }

    var name: String { type.frenchName }
    var symbol: String { type.symbolName }
}

extension HKWorkoutActivityType {
    var frenchName: String {
        switch self {
        case .running: return "Course à pied"
        case .walking: return "Marche"
        case .hiking: return "Randonnée"
        case .cycling: return "Vélo"
        case .swimming: return "Natation"
        case .traditionalStrengthTraining: return "Musculation"
        case .functionalStrengthTraining: return "Renforcement fonctionnel"
        case .highIntensityIntervalTraining: return "HIIT"
        case .crossTraining: return "Cross training"
        case .coreTraining: return "Gainage"
        case .mixedCardio: return "Cardio"
        case .elliptical: return "Elliptique"
        case .rowing: return "Rameur"
        case .stairClimbing: return "Escaliers"
        case .yoga: return "Yoga"
        case .soccer: return "Football"
        case .basketball: return "Basket"
        case .tennis: return "Tennis"
        case .boxing: return "Boxe"
        case .martialArts: return "Arts martiaux"
        case .socialDance, .cardioDance: return "Danse"
        case .climbing: return "Escalade"
        default: return "Autre activité"
        }
    }

    var symbolName: String {
        switch self {
        case .running: return "figure.run"
        case .walking: return "figure.walk"
        case .hiking: return "figure.hiking"
        case .cycling: return "figure.outdoor.cycle"
        case .swimming: return "figure.pool.swim"
        case .traditionalStrengthTraining: return "figure.strengthtraining.traditional"
        case .functionalStrengthTraining: return "figure.strengthtraining.functional"
        case .highIntensityIntervalTraining: return "figure.highintensity.intervaltraining"
        case .crossTraining: return "figure.cross.training"
        case .coreTraining: return "figure.core.training"
        case .elliptical: return "figure.elliptical"
        case .rowing: return "figure.rower"
        case .stairClimbing: return "figure.stair.stepper"
        case .yoga: return "figure.yoga"
        case .soccer: return "figure.soccer"
        case .basketball: return "figure.basketball"
        case .tennis: return "figure.tennis"
        case .boxing: return "figure.boxing"
        case .martialArts: return "figure.martial.arts"
        case .socialDance, .cardioDance: return "figure.dance"
        case .climbing: return "figure.climbing"
        default: return "figure.mixed.cardio"
        }
    }
}
