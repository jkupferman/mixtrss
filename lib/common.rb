class Common
  # Common bits that both the sinatra app and track refresher need to access
  AVAILABLE_GENRES = ["all", "bass", "dance", "deep",
                      "drum & bass", "dubstep",
                      "electro", "house", "mashup",
                      "techno", "trance", "tropical"]

  def self.genre_key genre
    "toptracks/#{genre}"
  end
end
