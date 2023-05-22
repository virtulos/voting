// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface FANATICO {
    function balanceOf(address account) external view returns (uint256);

    function unlockedBalanceOf(address account) external view returns (uint256);

    function lockedVotingTokens(address account) external view returns (uint256);

    function decimals() external view returns (uint8);
}


contract Voting is AccessControl, ReentrancyGuard {
    bytes32 private constant MODERATOR_ROLE = keccak256("MODERATOR_ROLE");

    constructor(address _token, address _owner) {
        votableToken = FANATICO(_token);

        _setupRole(DEFAULT_ADMIN_ROLE, _owner);
        _setupRole(MODERATOR_ROLE, _owner);
    }

    struct Proposal {
        address creator;
        bytes32 description;
        uint32 votingEndTime;
        uint32 votingDuration;
        uint64 numberOfVoters;
        uint8 numberOfOutcomes;
        uint8 winningOutcome;
        bool executed;
        bool active;
    }

    struct Outcome {
        address creator;
        uint64 numberOfVoters;
        bytes32 description;
        uint256 votes;
    }


    FANATICO public immutable votableToken;


    uint16 public numProposals;

    mapping(uint16 => Proposal) public proposals;
    mapping(uint16 => mapping(uint8 => Outcome)) public outcomes;
    mapping(uint16 => mapping(address => uint256)) public votingPowerPerProposal;
    mapping(uint16 => mapping(address => bool)) public hasVoted; // defines if a certain address voted for a proposal
    mapping(address => uint256) public fixedVotingPower;

    event VoteCast(address indexed voter, uint16 indexed proposalId, uint16 indexed outcomeId, uint256 votingPower);
    event ProposalAdded(address indexed creator, uint256 indexed proposalId, bytes32 description);
    event ProposalExecuted(uint16 indexed proposalId, uint16 indexed winningOutcome);
    event OutcomeAdded(uint16 indexed proposalId, uint16 indexed outcomeId, bytes32 description);

    modifier existingProposal(uint16 proposalId) {
        require(proposals[proposalId].creator != address(0), "Proposal does not exist");
        _;
    }

    function addModerator(address account) public onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(MODERATOR_ROLE, account);
    }

    function addProposal(bytes32 description, uint32 votingDuration) public onlyRole(MODERATOR_ROLE) {
        require(description != "", "Empty proposal description");
        require(votingDuration > 0, "Zero voting duration");

        Proposal memory proposal;
        proposal.creator = msg.sender;
        proposal.description = description;
        proposal.votingDuration = votingDuration;

        proposals[numProposals] = proposal;

        emit ProposalAdded(msg.sender, numProposals, description);

        numProposals++;
    }


    function addProposalDays(bytes32 description, uint32 votingDurationDays) public onlyRole(MODERATOR_ROLE) {
        addProposal(description, uint32(votingDurationDays * (1 days)));
    }


    function addProposalHours(bytes32 description, uint32 votingDurationHours) public onlyRole(MODERATOR_ROLE) {
        addProposal(description, uint32(votingDurationHours * (1 hours)));
    }


    function addOutcome(uint16 proposalId, bytes32 description) public onlyRole(MODERATOR_ROLE) existingProposal(proposalId) {
        require(description != "", "Empty outcome description");

        Proposal storage proposal = proposals[proposalId];
        require(proposal.active == false, "Proposal already active");
        require(proposal.numberOfOutcomes < type(uint8).max - 2, "Too many outcomes");

        Outcome memory outcome;
        outcome.creator = msg.sender;
        outcome.description = description;

        outcomes[proposalId][proposal.numberOfOutcomes] = outcome;

        uint8 outcomeId = uint8(proposal.numberOfOutcomes);
        proposal.numberOfOutcomes++;

        emit OutcomeAdded(proposalId, outcomeId, description);
    }

        function activateProposal(uint16 proposalId) public onlyRole(MODERATOR_ROLE) existingProposal(proposalId) {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.active == false, "Proposal already active");
        require(proposal.numberOfOutcomes > 0, "Proposal has no outcomes");

        proposal.active = true;
        proposal.votingEndTime = uint32(block.timestamp + proposal.votingDuration);
    }

    function _vote(address voter, uint16 proposalId, uint8 outcomeId, uint256 power) private {
        // if first time voting, set voting power based on unlocked balance
        if (fixedVotingPower[voter] == 0) {
            uint256 voterUnlockedBalance = votableToken.unlockedBalanceOf(voter);
            uint256 lockedVotesFlashLoan = votableToken.lockedVotingTokens(voter);
            require(voterUnlockedBalance > 0, "No unlocked balance");
            require(lockedVotesFlashLoan < voterUnlockedBalance, "Flash loans cannot be used to vote");

            voterUnlockedBalance -= lockedVotesFlashLoan;
            require(voterUnlockedBalance >= 1 * (10 ** votableToken.decimals()), "Minimum 1 FANATICO token required");

            fixedVotingPower[voter] = 10 * voterUnlockedBalance / (10 ** votableToken.decimals());
            votingPowerPerProposal[proposalId][voter] = fixedVotingPower[voter];
        }

        uint maxVotingCast;
        if (hasVoted[proposalId][voter] == true) {
            maxVotingCast = votingPowerPerProposal[proposalId][voter];
        } else {
            votingPowerPerProposal[proposalId][voter] = fixedVotingPower[voter];
            maxVotingCast = fixedVotingPower[voter];
        }

        require(maxVotingCast > 0, "No power to vote");
        require(power <= maxVotingCast, "Max power reached");

        Proposal storage proposal = proposals[proposalId];
        require(proposal.active == true, "Proposal not active");
        require(proposal.votingEndTime > block.timestamp, "Voting ended");
        require(outcomes[proposalId][outcomeId].creator != address(0), "Outcome does not exist");

        if (hasVoted[proposalId][voter] == false) {
            proposal.numberOfVoters++;
            outcomes[proposalId][outcomeId].numberOfVoters++;
            hasVoted[proposalId][voter] = true;
        }

        outcomes[proposalId][outcomeId].votes += power;
        votingPowerPerProposal[proposalId][voter] -= power;

        emit VoteCast(_msgSender(), proposalId, outcomeId, power);
    }

    function vote(uint16 proposalId, uint8 outcomeId, uint256 votingPowerToSpend) public nonReentrant existingProposal(proposalId) {
        _vote(_msgSender(), proposalId, outcomeId, votingPowerToSpend);
    }

    function executeProposal(uint16 proposalId) public onlyRole(MODERATOR_ROLE) existingProposal(proposalId) {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.executed == false, "Proposal already executed");
        require(proposal.active == true, "Proposal not active");
        require(proposal.numberOfVoters > 0, "No votes made");
        require(proposal.votingEndTime < block.timestamp, "Voting not ended");

        uint256 winningOutcomeVotes = 0;
        for(uint8 i = 0; i < proposal.numberOfOutcomes; i++) {
            if (outcomes[proposalId][i].votes > winningOutcomeVotes) {
                winningOutcomeVotes = outcomes[proposalId][i].votes;
                proposal.winningOutcome = i;
            }
        }

        proposal.executed = true;
        emit ProposalExecuted(proposalId, proposal.winningOutcome);
    }


    function stringToBytes32(string memory str) public pure returns (bytes32 result) {
        bytes memory temp = bytes(str);
        if (temp.length == 0) {
            return 0x0;
        }

        assembly {
            result := mload(add(temp, 32))
        }
    }
}
