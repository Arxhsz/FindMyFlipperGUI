#pragma once

#include "../Models/AppModels.h"

namespace FindMyFlipper::Services {
class ProfileStore final {
public:
  ProfileStore();
  bool OnboardingComplete() const noexcept;
  void SetOnboardingComplete(bool complete);
  Models::FlipperProfile const &Profile() const noexcept;
  Models::KeyIdentity const &Key() const noexcept;
  void UpdateProfile(Models::FlipperProfile const &profile);
  void UpdateKey(Models::KeyIdentity const &key);
  void Reset();

private:
  void Load();
  void Save() const;
  std::filesystem::path m_path;
  bool m_onboardingComplete{false};
  Models::FlipperProfile m_profile;
  Models::KeyIdentity m_key;
};
} // namespace FindMyFlipper::Services
