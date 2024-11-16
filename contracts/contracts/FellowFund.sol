// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IFellowFund} from "./interfaces/IFellowFund.sol";
import {Fellowship, Application, FellowshipStatus} from "./Types.sol";
import {Market} from "./Market.sol";
import {IMarket} from "./interfaces/IMarket.sol";
import "./Types.sol";

contract FellowFund is IFellowFund, Ownable {
    uint256 public fellowshipCount;
    mapping(uint256 => Fellowship) public fellowships;
    mapping(uint256 => Application[]) public applications;
    mapping(uint256 => mapping(uint256 => IMarket)) public markets;

    address public phalaVerifier;
    address public operator;

    constructor(address _phalaVerifier, address _operator) Ownable(msg.sender) {
        phalaVerifier = _phalaVerifier;
        operator = _operator;
    }

    modifier onlyVerifier() {
        // require(msg.sender == verifier, "Only the verifier can call this function");
        _;
    }

    modifier onlyOperator() {
        require(msg.sender == operator, "Only the operator can call this function");
        _;
    }

    function createFellowship(Fellowship calldata _fellowship) external payable {
        require(msg.value == _fellowship.funds, "Incorrect funds sent");
        require(_fellowship.applicationDeadline > block.timestamp, "Invalid application deadline");
        require(_fellowship.marketDeadline > _fellowship.applicationDeadline, "Invalid market deadline");
        require(_fellowship.epochEndTime > _fellowship.marketDeadline, "Invalid epoch end time");

        require(_fellowship.maxApplicants > 0, "Invalid max applicants");

        uint256 fellowshipId = fellowshipCount++;
        fellowships[fellowshipId] = _fellowship;
        fellowships[fellowshipId].status = FellowshipStatus.AcceptingApplications;

        emit FellowshipCreated(fellowshipId, fellowships[fellowshipId]);
    }

    function applyToFellowship(uint256 fellowshipId, string calldata metadata) external {
        Fellowship storage fellowship = fellowships[fellowshipId];
        require(fellowship.status == FellowshipStatus.AcceptingApplications, "Not accepting applications");
        require(block.timestamp < fellowship.applicationDeadline, "Application period ended");
        require(applications[fellowshipId].length < fellowship.maxApplicants, "Maximum applicants reached");

        // Todo: Add vlayer verification logic here - use vlayerProof as parameter

        uint256 applicationId = applications[fellowshipId].length;
        applications[fellowshipId].push(
            Application({
                applicant: msg.sender,
                metadata: metadata,
                achieved: false,
                verified: false,
                accepted: false,
                grantAmount: 0
            })
        );

        emit ApplicationSubmitted(fellowshipId, applicationId, msg.sender);
    }

    function openFellowshipMarkets(uint256 fellowshipId) external onlyOperator {
        Fellowship storage fellowship = fellowships[fellowshipId];
        require(block.timestamp >= fellowship.applicationDeadline, "Application period not ended");
        require(fellowship.status == FellowshipStatus.AcceptingApplications, "Invalid status");

        Application[] storage apps = applications[fellowshipId];
        require(apps.length > 0, "No applications to create markets for");

        // Create market for each applicant
        for (uint256 i = 0; i < apps.length; i++) {
            Market market = new Market(address(this), fellowshipId, apps[i].applicant);
            markets[fellowshipId][i] = IMarket(address(market));

            // Emit event for each market creation
            emit MarketOpened(fellowshipId, address(market));
        }

        fellowship.status = FellowshipStatus.MarketOpen;
    }

    function evaluateMarket(uint256 fellowshipId) external onlyOperator {
        Fellowship storage fellowship = fellowships[fellowshipId];
        require(block.timestamp >= fellowship.marketDeadline, "Market still open");
        require(fellowship.status == FellowshipStatus.MarketOpen, "Invalid status");

        Application[] storage apps = applications[fellowshipId];
        uint256 acceptedCount = 0;

        uint256 nrApps = apps.length;
        // Evaluate each application based on market stakes
        for (uint256 i = 0; i < nrApps; i++) {
            Application storage app = apps[i];
            IMarket market = markets[fellowshipId][i];
            uint256 yesStakes = market.getBet(Side.Yes);
            uint256 noStakes = market.getBet(Side.No);
            uint256 totalStakes = noStakes + noStakes;

            if (totalStakes > 0) {
                if (yesStakes > noStakes) {
                    app.accepted = true;
                    acceptedCount++;
                }
            }
        }

        // Calculate grant amount for accepted applications
        if (acceptedCount > 0) {
            uint256 grantPerAccepted = fellowship.funds / acceptedCount;
            for (uint256 i = 0; i < apps.length; i++) {
                if (apps[i].accepted) {
                    apps[i].grantAmount = grantPerAccepted;
                    payable(apps[i].applicant).transfer(grantPerAccepted);
                }
            }
        }

        fellowship.status = FellowshipStatus.EpochStarted;
        emit EpochStarted(fellowshipId);
    }

    function setApplicantImpact(uint256 fellowshipId, uint256 applicationId, bool achieved, bytes calldata proof)
        external
        onlyVerifier
    {
        require(fellowships[fellowshipId].status == FellowshipStatus.EpochStarted, "Invalid status");

        // Verify TEE proof
        (bool success,) = phalaVerifier.call(proof);
        require(success, "Invalid achievement proof");

        Application storage application = applications[fellowshipId][applicationId];
        application.achieved = achieved;
        application.verified = true;
    }

    function resolveFellowship(uint256 fellowshipId) external onlyOperator {
        Fellowship storage fellowship = fellowships[fellowshipId];
        require(block.timestamp >= fellowship.epochEndTime, "Epoch not ended");
        require(fellowship.status == FellowshipStatus.EpochStarted, "Invalid status");

        Application[] storage apps = applications[fellowshipId];
        for (uint256 i = 0; i < apps.length; i++) {
            Application storage app = apps[i];
            require(app.verified, "Not all applications verified");

            if (app.achieved) {
                markets[fellowshipId][i].resolve(Side.Yes);
            } else {
                markets[fellowshipId][i].resolve(Side.No);
            }
        }

        fellowship.status = FellowshipStatus.Resolved;
        emit FellowshipResolved(fellowshipId);
    }

    function setVerifier(address _verifier) external onlyOwner {
        phalaVerifier = _verifier;
    }

    function setOperator(address _operator) external onlyOwner {
        operator = _operator;
    }
}
