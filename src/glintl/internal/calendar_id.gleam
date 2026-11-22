pub type CalendarId {
  Gregorian
  Iso8601
  Buddhist
  Japanese
  RepublicOfChina
  Persian
  Indian
  Hebrew
  Chinese
  Dangi
  Coptic
  Ethiopic
  EthiopicAmeteAlem
  IslamicCivil
  IslamicTabular
  IslamicUmmAlQura
}

pub fn name(id: CalendarId) -> String {
  case id {
    Gregorian -> "gregory"
    Iso8601 -> "iso8601"
    Buddhist -> "buddhist"
    Japanese -> "japanese"
    RepublicOfChina -> "roc"
    Persian -> "persian"
    Indian -> "indian"
    Hebrew -> "hebrew"
    Chinese -> "chinese"
    Dangi -> "dangi"
    Coptic -> "coptic"
    Ethiopic -> "ethiopic"
    EthiopicAmeteAlem -> "ethioaa"
    IslamicCivil -> "islamic-civil"
    IslamicTabular -> "islamic-tbla"
    IslamicUmmAlQura -> "islamic-umalqura"
  }
}
