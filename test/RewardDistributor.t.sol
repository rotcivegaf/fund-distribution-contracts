// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

// import "./src/RewardDistributor.sol";
import "../src/RewardDistributor.sol";
import "./Reverter.sol";
import "forge-std/Test.sol";

contract EmptyContract {}

contract UsesTooMuchGasContract {
    receive() external payable {
        // 1k iterations should use at least 100k gas
        uint256 j = 0;
        for (uint256 i; i < 1000; i++) {
            j++;
        }
    }
}

contract RewardDistributorTest is Test {
    address a = vm.addr(0x01);
    address b = vm.addr(0x02);
    address c = vm.addr(0x03);
    address owner = vm.addr(0x04);
    address nobody = vm.addr(0x05);

    function clearAccounts() public {
        vm.deal(a, 0);
        vm.deal(b, 0);
        vm.deal(c, 0);
        vm.deal(owner, 0);
        vm.deal(nobody, 0);
    }

    function makeRecipientGroup(uint256 count) private view returns (address[] memory) {
        address[] memory recipients = new address[](count);
        if (0 < count) {
            recipients[0] = a;
        }
        if (1 < count) {
            recipients[1] = b;
        }
        if (2 < count) {
            recipients[2] = c;
        }
        return recipients;
    }

    function testConstructor() public {
        clearAccounts();
        address[] memory recipients = makeRecipientGroup(3);

        vm.prank(owner);
        RewardDistributor rd = new RewardDistributor(recipients);

        assertEq(rd.currentRecipientGroup(), keccak256(abi.encodePacked(recipients)));
        assertEq(rd.owner(), owner);
    }

    function testConstructorDoesNotAcceptEmpty() public {
        clearAccounts();
        address[] memory recipients = makeRecipientGroup(0);

        vm.prank(owner);
        vm.expectRevert(EmptyRecipients.selector);
        new RewardDistributor(recipients);
    }

    function testDistributeRewards() public {
        clearAccounts();
        address[] memory recipients = makeRecipientGroup(3);

        vm.prank(owner);
        RewardDistributor rd = new RewardDistributor(recipients);

        // increase the balance of rd
        uint256 reward = 1e8;
        vm.deal(address(rd), reward);

        vm.prank(nobody);
        rd.distributeRewards(recipients);

        uint256 aReward = reward / 3;
        assertEq(a.balance, aReward, "a balance");
        assertEq(b.balance, aReward, "b balance");
        assertEq(c.balance, aReward + reward % 3, "c balance");
        assertEq(owner.balance, 0, "owner balance");
        assertEq(nobody.balance, 0, "nobody balance");
    }

    function testDistributeRewardsDoesRefundsOwner() public {
        clearAccounts();
        address[] memory recipients = makeRecipientGroup(3);

        vm.prank(owner);
        RewardDistributor rd = new RewardDistributor(recipients);

        // the empty contract will revert when sending funds to it, as it doesn't
        // have a fallback. We set the c address to have this code
        UsesTooMuchGasContract ec = new UsesTooMuchGasContract();
        vm.etch(c, address(ec).code);

        // increase the balance of rd
        uint256 reward = 1e8;
        vm.deal(address(rd), reward);

        vm.prank(nobody);
        rd.distributeRewards(recipients);

        uint256 aReward = reward / 3;
        assertEq(a.balance, aReward, "a balance");
        assertEq(b.balance, aReward, "b balance");
        assertEq(c.balance, 0, "c balance");
        assertEq(owner.balance, aReward + reward % 3, "owner balance");
        assertEq(nobody.balance, 0, "nobody balance");
    }

    function testDistributeRewardsDoesNotDistributeToEmpty() public {
        clearAccounts();
        address[] memory recipients = makeRecipientGroup(3);

        vm.prank(owner);
        RewardDistributor rd = new RewardDistributor(recipients);

        // increase the balance of rd
        uint256 reward = 1e8;
        vm.deal(address(rd), reward);

        vm.expectRevert(EmptyRecipients.selector);
        address[] memory emptyRecipients = makeRecipientGroup(0);
        vm.prank(nobody);
        rd.distributeRewards(emptyRecipients);
    }

    function testDistributeRewardsDoesNotDistributeWrongRecipients() public {
        clearAccounts();
        address[] memory recipients = makeRecipientGroup(3);

        vm.prank(owner);
        RewardDistributor rd = new RewardDistributor(recipients);

        // increase the balance of rd
        uint256 reward = 1e8;
        vm.deal(address(rd), reward);

        address[] memory wrongRecipients = new address[](3);
        wrongRecipients[0] = a;
        wrongRecipients[1] = b;
        // wrong recipient
        wrongRecipients[2] = nobody;
        vm.expectRevert(
            abi.encodeWithSelector(
                InvalidRecipientGroup.selector, rd.currentRecipientGroup(), keccak256(abi.encodePacked(wrongRecipients))
            )
        );
        vm.prank(nobody);
        rd.distributeRewards(wrongRecipients);
    }

    function testDistributeRewardsDoesNotDistributeToWrongCount() public {
        clearAccounts();
        address[] memory recipients = makeRecipientGroup(3);

        vm.prank(owner);
        RewardDistributor rd = new RewardDistributor(recipients);

        // increase the balance of rd
        uint256 reward = 1e8;
        vm.deal(address(rd), reward);

        address[] memory shortRecipients = makeRecipientGroup(2);
        vm.expectRevert(
            abi.encodeWithSelector(
                InvalidRecipientGroup.selector, rd.currentRecipientGroup(), keccak256(abi.encodePacked(shortRecipients))
            )
        );
        vm.prank(nobody);
        rd.distributeRewards(shortRecipients);
    }

    function testDistributeRewardsFailsToRefundsOwner() public {
        clearAccounts();
        address[] memory recipients = makeRecipientGroup(3);

        vm.prank(owner);
        RewardDistributor rd = new RewardDistributor(recipients);

        // the empty contract will revert when sending funds to it, as it doesn't
        // have a fallback. We set the c address and the owner to have this code
        EmptyContract ec = new EmptyContract();
        vm.etch(c, address(ec).code);
        vm.etch(owner, address(ec).code);

        // increase the balance of rd
        uint256 reward = 1e8;
        vm.deal(address(rd), reward);

        vm.expectRevert(abi.encodeWithSelector(OwnerFailedRecieve.selector, owner, c, (reward / 3) + reward % 3));
        vm.prank(nobody);
        rd.distributeRewards(recipients);
    }

    function testBlockGasLimit() public {
        uint64 numReverters = 64;
        address[] memory recipients = new address[](numReverters);
        for (uint256 i = 0; i < recipients.length; i++) {
            recipients[i] = address(new Reverter());
        }
        RewardDistributor rd = new RewardDistributor(recipients);

        assertEq(numReverters, rd.MAX_RECIPIENTS());

        // TODO: fuzz this value?
        vm.deal(address(rd), 5 ether);

        uint256 gasleftPrior = gasleft();
        emit log_named_uint("gas left prior", gasleftPrior);

        rd.distributeRewards(recipients);

        uint256 gasleftAfter = gasleft();
        emit log_named_uint("gas left after", gasleftAfter);

        uint256 gasUsed = gasleftPrior - gasleftAfter;
        emit log_named_uint("gas left used", gasUsed);
        
        uint256 blockGasLimit = 32_000_000;
        // must fit within block gas limit (this value may change in the future)
        // block.gaslimit >= PER_RECIPIENT_GAS * MAX_RECIPIENTS + SEND_ALL_FIXED_GAS
        assertTrue(blockGasLimit >= gasUsed);
        assertTrue(gasUsed >= rd.PER_RECIPIENT_GAS() * rd.MAX_RECIPIENTS());
    }

    // this is triggered when the owner fallback is called
    receive() external payable {}
}
