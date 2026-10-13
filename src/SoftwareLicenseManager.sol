// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @notice Non-transferable, wallet-bound software licenses for a course project.
/// @dev Metadata and source/binaries live off chain. No payment or wallet authentication here.
contract SoftwareLicenseManager is AccessControl {
    bytes32 public constant PUBLISHER_ROLE = keccak256("PUBLISHER_ROLE");

    struct Software {
        address publisher;
        string name;
        string version;
        string metadataURI;
        bytes32 artifactHash;
        bool active;
    }

    struct License {
        uint256 softwareId;
        address holder;
        uint64 expiresAt;
        bool revoked;
    }

    uint256 public softwareCount;
    uint256 public licenseCount;
    mapping(uint256 => Software) private softwares;
    mapping(uint256 => License) private licenses;
    /// @notice Latest license ID per software and holder; zero means none.
    mapping(uint256 => mapping(address => uint256)) public licenseOf;

    error ZeroAddress();
    error EmptyMetadata();
    error SoftwareNotFound(uint256 softwareId);
    error LicenseNotFound(uint256 licenseId);
    error NotSoftwarePublisher(uint256 softwareId);
    error SoftwareInactive(uint256 softwareId);
    error InvalidExpiration();
    error LicenseAlreadyExists(uint256 licenseId);
    error LicenseRevoked(uint256 licenseId);

    event SoftwareRegistered(uint256 indexed softwareId, address indexed publisher, bytes32 artifactHash);
    event SoftwareStatusChanged(uint256 indexed softwareId, bool active);
    event LicenseIssued(uint256 indexed licenseId, uint256 indexed softwareId, address indexed holder, uint64 expiresAt);
    event LicenseRenewed(uint256 indexed licenseId, uint64 oldExpiresAt, uint64 newExpiresAt);
    event LicenseRevokedEvent(uint256 indexed licenseId, uint256 indexed softwareId, address indexed holder);

    constructor(address admin, address initialPublisher) {
        if (admin == address(0) || initialPublisher == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PUBLISHER_ROLE, initialPublisher);
    }

    function registerSoftware(
        string calldata name,
        string calldata version,
        string calldata metadataURI,
        bytes32 artifactHash
    ) external onlyRole(PUBLISHER_ROLE) returns (uint256 softwareId) {
        if (bytes(name).length == 0 || bytes(version).length == 0 || bytes(metadataURI).length == 0) {
            revert EmptyMetadata();
        }
        softwareId = ++softwareCount;
        softwares[softwareId] = Software(msg.sender, name, version, metadataURI, artifactHash, true);
        emit SoftwareRegistered(softwareId, msg.sender, artifactHash);
    }

    /// @notice Deactivation suspends validation of all licenses for this software.
    /// Reactivation restores still-unexpired, non-revoked licenses.
    function setSoftwareActive(uint256 softwareId, bool active) external onlyRole(PUBLISHER_ROLE) {
        Software storage software = _ownedSoftware(softwareId);
        software.active = active;
        emit SoftwareStatusChanged(softwareId, active);
    }

    /// @notice Reissue after revocation creates a new ID and preserves the old record.
    /// An expired, non-revoked license must be renewed instead of reissued.
    function issueLicense(uint256 softwareId, address holder, uint64 expiresAt)
        external onlyRole(PUBLISHER_ROLE) returns (uint256 licenseId)
    {
        Software storage software = _ownedSoftware(softwareId);
        if (!software.active) revert SoftwareInactive(softwareId);
        if (holder == address(0)) revert ZeroAddress();
        if (expiresAt <= block.timestamp) revert InvalidExpiration();
        uint256 existingId = licenseOf[softwareId][holder];
        if (existingId != 0 && !licenses[existingId].revoked) revert LicenseAlreadyExists(existingId);
        licenseId = ++licenseCount;
        licenses[licenseId] = License(softwareId, holder, expiresAt, false);
        licenseOf[softwareId][holder] = licenseId;
        emit LicenseIssued(licenseId, softwareId, holder, expiresAt);
    }

    function renewLicense(uint256 licenseId, uint64 newExpiresAt) external onlyRole(PUBLISHER_ROLE) {
        License storage license = _license(licenseId);
        Software storage software = _ownedSoftware(license.softwareId);
        if (!software.active) revert SoftwareInactive(license.softwareId);
        if (license.revoked) revert LicenseRevoked(licenseId);
        if (newExpiresAt <= block.timestamp || newExpiresAt <= license.expiresAt) revert InvalidExpiration();
        uint64 previous = license.expiresAt;
        license.expiresAt = newExpiresAt;
        emit LicenseRenewed(licenseId, previous, newExpiresAt);
    }

    function revokeLicense(uint256 licenseId) external onlyRole(PUBLISHER_ROLE) {
        License storage license = _license(licenseId);
        _ownedSoftware(license.softwareId);
        if (license.revoked) revert LicenseRevoked(licenseId);
        license.revoked = true;
        emit LicenseRevokedEvent(licenseId, license.softwareId, license.holder);
    }

    /// @notice A read-only entitlement check, not proof of wallet ownership.
    /// The consuming app must authenticate holder via a fresh signed challenge.
    function isLicenseValid(uint256 softwareId, address holder) external view returns (bool) {
        uint256 licenseId = licenseOf[softwareId][holder];
        if (licenseId == 0) return false;
        License storage license = licenses[licenseId];
        return softwares[softwareId].active && !license.revoked && block.timestamp < license.expiresAt;
    }

    function getSoftware(uint256 softwareId) external view returns (Software memory) {
        return _software(softwareId);
    }

    function getLicense(uint256 licenseId) external view returns (License memory) {
        return _license(licenseId);
    }

    function _software(uint256 softwareId) private view returns (Software storage software) {
        software = softwares[softwareId];
        if (software.publisher == address(0)) revert SoftwareNotFound(softwareId);
    }

    function _ownedSoftware(uint256 softwareId) private view returns (Software storage software) {
        software = _software(softwareId);
        if (software.publisher != msg.sender) revert NotSoftwarePublisher(softwareId);
    }

    function _license(uint256 licenseId) private view returns (License storage license) {
        license = licenses[licenseId];
        if (license.holder == address(0)) revert LicenseNotFound(licenseId);
    }
}
