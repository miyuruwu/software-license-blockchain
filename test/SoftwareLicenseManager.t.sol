// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {SoftwareLicenseManager} from "../src/SoftwareLicenseManager.sol";
import {Deploy} from "../script/Deploy.s.sol";

// Minimal Foundry cheatcode interface; no forge-std dependency required.
interface Vm {
    function prank(address sender) external;
    function warp(uint256 timestamp) external;
    function expectRevert(bytes calldata revertData) external;
    function expectEmit(bool topic1, bool topic2, bool topic3, bool data, address emitter) external;
    function setEnv(string calldata name, string calldata value) external;
    function toString(address value) external pure returns (string memory);
}

contract SoftwareLicenseManagerTest {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    SoftwareLicenseManager private manager;
    address private constant ADMIN = address(0xA11);
    address private constant PUBLISHER = address(0xB11);
    address private constant OTHER_PUBLISHER = address(0xB22);
    address private constant USER = address(0xC11);
    address private constant STRANGER = address(0xD11);
    uint256 private softwareId;
    uint64 private constant EXPIRY = 10_000;

    event LicenseIssued(uint256 indexed licenseId, uint256 indexed softwareId, address indexed holder, uint64 expiresAt);

    function setUp() public {
        vm.warp(1_000);
        manager = new SoftwareLicenseManager(ADMIN, PUBLISHER);
        bytes32 publisherRole = manager.PUBLISHER_ROLE();
        vm.prank(ADMIN);
        manager.grantRole(publisherRole, OTHER_PUBLISHER);
        vm.prank(PUBLISHER);
        softwareId = manager.registerSoftware("Demo Editor", "1.0", "https://example.com/demo.json", keccak256("demo-binary"));
    }

    function _issue() private returns (uint256) {
        vm.prank(PUBLISHER);
        return manager.issueLicense(softwareId, USER, EXPIRY);
    }

    function _unauthorized(address caller, bytes32 role) private pure returns (bytes memory) {
        return abi.encodeWithSignature("AccessControlUnauthorizedAccount(address,bytes32)", caller, role);
    }

    function testRegistrationStoresPublisherAndMetadata() public view {
        SoftwareLicenseManager.Software memory software = manager.getSoftware(softwareId);
        require(software.publisher == PUBLISHER && software.active, "wrong publisher/status");
        require(keccak256(bytes(software.name)) == keccak256("Demo Editor"), "wrong name");
        require(software.artifactHash == keccak256("demo-binary"), "wrong artifact hash");
    }

    function testDeployScriptAssignsConfiguredRoles() public {
        vm.setEnv("ADMIN_ADDRESS", vm.toString(ADMIN));
        vm.setEnv("PUBLISHER_ADDRESS", vm.toString(PUBLISHER));
        SoftwareLicenseManager deployed = new Deploy().run();
        require(deployed.hasRole(deployed.DEFAULT_ADMIN_ROLE(), ADMIN), "deploy admin incorrect");
        require(deployed.hasRole(deployed.PUBLISHER_ROLE(), PUBLISHER), "deploy publisher incorrect");
        require(!deployed.hasRole(deployed.DEFAULT_ADMIN_ROLE(), PUBLISHER), "publisher became admin");
    }

    function testRejectsZeroAdmin() public {
        vm.expectRevert(abi.encodeWithSelector(SoftwareLicenseManager.ZeroAddress.selector));
        new SoftwareLicenseManager(address(0), PUBLISHER);
    }

    function testRejectsZeroInitialPublisher() public {
        vm.expectRevert(abi.encodeWithSelector(SoftwareLicenseManager.ZeroAddress.selector));
        new SoftwareLicenseManager(ADMIN, address(0));
    }

    function testUnauthorizedCannotRegister() public {
        vm.expectRevert(_unauthorized(STRANGER, manager.PUBLISHER_ROLE()));
        vm.prank(STRANGER);
        manager.registerSoftware("App", "1", "uri", bytes32(0));
    }

    function testEmptyMetadataRejected() public {
        vm.expectRevert(abi.encodeWithSelector(SoftwareLicenseManager.EmptyMetadata.selector));
        vm.prank(PUBLISHER);
        manager.registerSoftware("", "1", "uri", bytes32(0));
    }

    function testIssueEmitsEventAndBindsHolder() public {
        vm.expectEmit(true, true, true, true, address(manager));
        emit LicenseIssued(1, softwareId, USER, EXPIRY);
        uint256 licenseId = _issue();
        SoftwareLicenseManager.License memory license = manager.getLicense(licenseId);
        require(license.holder == USER && license.softwareId == softwareId, "wrong binding");
        require(manager.licenseOf(softwareId, USER) == licenseId, "wrong lookup");
        require(manager.isLicenseValid(softwareId, USER), "should be valid");
        require(!manager.isLicenseValid(softwareId, STRANGER), "stranger has entitlement");
        require(!manager.isLicenseValid(999, USER), "wrong software has entitlement");
    }

    function testUnauthorizedCannotIssue() public {
        vm.expectRevert(_unauthorized(STRANGER, manager.PUBLISHER_ROLE()));
        vm.prank(STRANGER);
        manager.issueLicense(softwareId, USER, EXPIRY);
    }

    function testOtherPublisherCannotIssueForAnotherSoftware() public {
        vm.expectRevert(abi.encodeWithSelector(SoftwareLicenseManager.NotSoftwarePublisher.selector, softwareId));
        vm.prank(OTHER_PUBLISHER);
        manager.issueLicense(softwareId, USER, EXPIRY);
    }

    function testRejectsUnknownSoftware() public {
        vm.expectRevert(abi.encodeWithSelector(SoftwareLicenseManager.SoftwareNotFound.selector, 99));
        vm.prank(PUBLISHER);
        manager.issueLicense(99, USER, EXPIRY);
    }

    function testRejectsZeroHolder() public {
        vm.expectRevert(abi.encodeWithSelector(SoftwareLicenseManager.ZeroAddress.selector));
        vm.prank(PUBLISHER);
        manager.issueLicense(softwareId, address(0), EXPIRY);
    }

    function testRejectsExpirationAtCurrentTimestamp() public {
        vm.expectRevert(abi.encodeWithSelector(SoftwareLicenseManager.InvalidExpiration.selector));
        vm.prank(PUBLISHER);
        manager.issueLicense(softwareId, USER, uint64(block.timestamp));
    }

    function testRejectsDuplicateEvenWhenExpired() public {
        uint256 licenseId = _issue();
        vm.warp(EXPIRY);
        vm.expectRevert(abi.encodeWithSelector(SoftwareLicenseManager.LicenseAlreadyExists.selector, licenseId));
        vm.prank(PUBLISHER);
        manager.issueLicense(softwareId, USER, EXPIRY + 100);
    }

    function testExpirationBoundary() public {
        _issue();
        vm.warp(EXPIRY - 1);
        require(manager.isLicenseValid(softwareId, USER), "expired too early");
        vm.warp(EXPIRY);
        require(!manager.isLicenseValid(softwareId, USER), "valid at expiration");
    }

    function testRenewExpiredLicense() public {
        uint256 licenseId = _issue();
        vm.warp(EXPIRY + 1);
        vm.prank(PUBLISHER);
        manager.renewLicense(licenseId, EXPIRY + 100);
        require(manager.isLicenseValid(softwareId, USER), "renewal ineffective");
        require(manager.licenseCount() == 1, "renewal created record");
    }

    function testCannotShortenOrKeepExpiration() public {
        uint256 licenseId = _issue();
        vm.expectRevert(abi.encodeWithSelector(SoftwareLicenseManager.InvalidExpiration.selector));
        vm.prank(PUBLISHER);
        manager.renewLicense(licenseId, EXPIRY - 1);
        vm.expectRevert(abi.encodeWithSelector(SoftwareLicenseManager.InvalidExpiration.selector));
        vm.prank(PUBLISHER);
        manager.renewLicense(licenseId, EXPIRY);
    }

    function testRenewMustEndInFuture() public {
        uint256 licenseId = _issue();
        vm.warp(EXPIRY + 200);
        vm.expectRevert(abi.encodeWithSelector(SoftwareLicenseManager.InvalidExpiration.selector));
        vm.prank(PUBLISHER);
        manager.renewLicense(licenseId, EXPIRY + 100);
    }

    function testRevokedCannotBeRenewed() public {
        uint256 licenseId = _issue();
        vm.prank(PUBLISHER);
        manager.revokeLicense(licenseId);
        require(!manager.isLicenseValid(softwareId, USER), "revoked license valid");
        vm.expectRevert(abi.encodeWithSelector(SoftwareLicenseManager.LicenseRevoked.selector, licenseId));
        vm.prank(PUBLISHER);
        manager.renewLicense(licenseId, EXPIRY + 100);
    }

    function testReissuePreservesRevokedRecord() public {
        uint256 oldId = _issue();
        vm.prank(PUBLISHER);
        manager.revokeLicense(oldId);
        uint256 newId = _issue();
        require(newId != oldId && manager.getLicense(oldId).revoked, "history lost");
        require(manager.licenseOf(softwareId, USER) == newId, "lookup not replaced");
        require(manager.isLicenseValid(softwareId, USER), "reissue invalid");
    }

    function testCannotRevokeTwice() public {
        uint256 licenseId = _issue();
        vm.prank(PUBLISHER);
        manager.revokeLicense(licenseId);
        vm.expectRevert(abi.encodeWithSelector(SoftwareLicenseManager.LicenseRevoked.selector, licenseId));
        vm.prank(PUBLISHER);
        manager.revokeLicense(licenseId);
    }

    function testOtherPublisherCannotRenewOrRevokeOrDeactivate() public {
        uint256 licenseId = _issue();
        bytes memory err = abi.encodeWithSelector(SoftwareLicenseManager.NotSoftwarePublisher.selector, softwareId);
        vm.expectRevert(err);
        vm.prank(OTHER_PUBLISHER);
        manager.renewLicense(licenseId, EXPIRY + 100);
        vm.expectRevert(err);
        vm.prank(OTHER_PUBLISHER);
        manager.revokeLicense(licenseId);
        vm.expectRevert(err);
        vm.prank(OTHER_PUBLISHER);
        manager.setSoftwareActive(softwareId, false);
    }

    function testDeactivationSuspendsAndReactivationRestores() public {
        _issue();
        vm.prank(PUBLISHER);
        manager.setSoftwareActive(softwareId, false);
        require(!manager.isLicenseValid(softwareId, USER), "inactive software valid");
        vm.prank(PUBLISHER);
        manager.setSoftwareActive(softwareId, true);
        require(manager.isLicenseValid(softwareId, USER), "reactivation ineffective");
    }

    function testInactiveCannotIssueOrRenewButCanRevoke() public {
        uint256 licenseId = _issue();
        vm.prank(PUBLISHER);
        manager.setSoftwareActive(softwareId, false);
        bytes memory err = abi.encodeWithSelector(SoftwareLicenseManager.SoftwareInactive.selector, softwareId);
        vm.expectRevert(err);
        vm.prank(PUBLISHER);
        manager.issueLicense(softwareId, STRANGER, EXPIRY);
        vm.expectRevert(err);
        vm.prank(PUBLISHER);
        manager.renewLicense(licenseId, EXPIRY + 100);
        vm.prank(PUBLISHER);
        manager.revokeLicense(licenseId);
        require(manager.getLicense(licenseId).revoked, "revocation blocked");
    }

    function testAdminControlsPublisherRole() public {
        bytes32 role = manager.PUBLISHER_ROLE();
        vm.expectRevert(_unauthorized(STRANGER, manager.DEFAULT_ADMIN_ROLE()));
        vm.prank(STRANGER);
        manager.grantRole(role, STRANGER);
        vm.prank(ADMIN);
        manager.revokeRole(role, PUBLISHER);
        vm.expectRevert(_unauthorized(PUBLISHER, role));
        vm.prank(PUBLISHER);
        manager.issueLicense(softwareId, USER, EXPIRY);
    }

    function testUnknownLicenseCannotBeRenewedOrRevoked() public {
        bytes memory err = abi.encodeWithSelector(SoftwareLicenseManager.LicenseNotFound.selector, 99);
        vm.expectRevert(err);
        vm.prank(PUBLISHER);
        manager.renewLicense(99, EXPIRY);
        vm.expectRevert(err);
        vm.prank(PUBLISHER);
        manager.revokeLicense(99);
    }

    function testFuzzLicenseValidOnlyBeforeExpiry(uint64 duration, address holder) public {
        // Bound without arithmetic overflow or assumptions.
        uint64 expiry = uint64(block.timestamp) + uint64(uint256(duration) % 365 days) + 1;
        if (holder == address(0)) holder = USER;
        vm.prank(PUBLISHER);
        manager.issueLicense(softwareId, holder, expiry);
        require(manager.isLicenseValid(softwareId, holder), "new license invalid");
        vm.warp(expiry);
        require(!manager.isLicenseValid(softwareId, holder), "expired license valid");
    }
}
