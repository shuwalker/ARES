import Foundation

enum AvatarStyle: String, CaseIterable, Codable {
    case blackFire
    case anime
    case hologram
    case blob
    case pixelVolume
    case constellation
    
    var surfaceShaderName: String {
        switch self {
        case .blackFire:      return "blackFireSurface"
        case .anime:          return "animeSurface"
        case .hologram:       return "hologramSurface"
        case .blob:           return "blobSurface"
        case .pixelVolume:   return "pixelVolumeSurface"
        case .constellation:  return "constellationSurface"
        }
    }
    
    var geometryModifierName: String {
        switch self {
        case .blackFire:      return "blackFireGeometry"
        case .anime:          return "animeGeometry"
        case .hologram:       return "hologramGeometry"
        case .blob:           return "blobGeometry"
        case .pixelVolume:   return "pixelVolumeGeometry"
        case .constellation:  return "constellationGeometry"
        }
    }
    
    var displayName: String {
        switch self {
        case .blackFire:      return "Black Fire"
        case .anime:          return "Anime"
        case .hologram:       return "Hologram"
        case .blob:           return "Blob"
        case .pixelVolume:   return "Pixel Volume"
        case .constellation:  return "Constellation"
        }
    }
    
    var icon: String {
        switch self {
        case .blackFire:      return "flame"
        case .anime:          return "sparkles.tv"
        case .hologram:       return "wave.3.forward"
        case .blob:           return "circle.circle"
        case .pixelVolume:   return "cube"
        case .constellation:  return "staroflife"
        }
    }
}